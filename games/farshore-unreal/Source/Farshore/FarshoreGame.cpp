#include "FarshoreGame.h"

#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "Components/InputComponent.h"
#include "Components/SkyLightComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/Canvas.h"
#include "Engine/DirectionalLight.h"
#include "Engine/Engine.h"
#include "Engine/SkyLight.h"
#include "Engine/StaticMeshActor.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/PlayerController.h"
#include "GameFramework/SpringArmComponent.h"
#include "Kismet/GameplayStatics.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "TimerManager.h"
#include "UObject/ConstructorHelpers.h"
#include "UnrealClient.h"

namespace
{
const TCHAR* SaveSlot()
{
#if WITH_DEV_AUTOMATION_TESTS
    if (FParse::Param(FCommandLine::Get(), TEXT("FarshoreSmoke"))) return TEXT("FarshoreAutomatedSmoke");
#endif
    return TEXT("FarshoreUnreal");
}
const FVector StartPosition(-800, -300, 90);
}

AFarshoreCharacter::AFarshoreCharacter()
{
    PrimaryActorTick.bCanEverTick = true;
    GetCapsuleComponent()->InitCapsuleSize(34, 88);
    GetCharacterMovement()->MaxWalkSpeed = 360;
    GetCharacterMovement()->bOrientRotationToMovement = false;
    bUseControllerRotationYaw = false;
    CameraArm = CreateDefaultSubobject<USpringArmComponent>(TEXT("CameraArm"));
    CameraArm->SetupAttachment(GetRootComponent());
    CameraArm->TargetArmLength = 1800;
    CameraArm->SetRelativeRotation(FRotator(-50, 0, 0));
    CameraArm->bDoCollisionTest = false;
    Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
    Camera->SetupAttachment(CameraArm);
    Camera->ProjectionMode = ECameraProjectionMode::Orthographic;
    Camera->OrthoWidth = 2100;

    static ConstructorHelpers::FObjectFinder<UStaticMesh> CubeMesh(TEXT("/Engine/BasicShapes/Cube.Cube"));
    static ConstructorHelpers::FObjectFinder<UMaterialInterface> Material(TEXT("/Game/Farshore/M_FarshoreTint.M_FarshoreTint"));
    auto MakePart = [&](const TCHAR* Name, FVector Location, FVector Scale, FLinearColor Color)
    {
        UStaticMeshComponent* Part = CreateDefaultSubobject<UStaticMeshComponent>(Name);
        Part->SetupAttachment(GetRootComponent());
        Part->SetRelativeLocation(Location);
        Part->SetRelativeScale3D(Scale);
        Part->SetCollisionEnabled(ECollisionEnabled::NoCollision);
        Part->SetStaticMesh(CubeMesh.Object);
        if (Material.Succeeded())
        {
            Part->SetMaterial(0, Material.Object);
            Part->SetVectorParameterValueOnMaterials(TEXT("Color"), FVector(Color.R, Color.G, Color.B));
        }
        return Part;
    };
    MakePart(TEXT("Head"), FVector(0, 0, 39), FVector(.16, .40, .40), FLinearColor(.8, .57, .41));
    MakePart(TEXT("Hair"), FVector(0, 0, 61), FVector(.18, .45, .11), FLinearColor(.15, .20, .22));
    MakePart(TEXT("Coat"), FVector(0, 0, -4), FVector(.18, .55, .50), FLinearColor(.20, .46, .46));
    LeftLeg = MakePart(TEXT("LeftLeg"), FVector(0, -12, -54), FVector(.17, .18, .45), FLinearColor(.17, .24, .24));
    RightLeg = MakePart(TEXT("RightLeg"), FVector(0, 12, -54), FVector(.17, .18, .45), FLinearColor(.17, .24, .24));
}

void AFarshoreCharacter::SetupPlayerInputComponent(UInputComponent* Input)
{
    Super::SetupPlayerInputComponent(Input);
    Input->BindAxis(TEXT("North"), this, &AFarshoreCharacter::North);
    Input->BindAxis(TEXT("East"), this, &AFarshoreCharacter::East);
    Input->BindAction(TEXT("Interact"), IE_Pressed, this, &AFarshoreCharacter::Interact);
}

void AFarshoreCharacter::North(float Value) { AddMovementInput(FVector::ForwardVector, Value); }
void AFarshoreCharacter::East(float Value) { AddMovementInput(FVector::RightVector, Value); }
void AFarshoreCharacter::Interact()
{
    if (AFarshoreGameMode* Game = GetWorld()->GetAuthGameMode<AFarshoreGameMode>()) Game->Interact();
}

void AFarshoreCharacter::Tick(float DeltaSeconds)
{
    Super::Tick(DeltaSeconds);
    const bool bMoving = GetVelocity().SizeSquared2D() > 25;
    WalkTime = bMoving ? WalkTime + DeltaSeconds : 0;
    const float Step = bMoving ? FMath::Sin(WalkTime * 10) * 13 : 0;
    LeftLeg->SetRelativeLocation(FVector(0, -12, -54 + Step));
    RightLeg->SetRelativeLocation(FVector(0, 12, -54 - Step));
}

AFarshoreGameMode::AFarshoreGameMode()
{
    DefaultPawnClass = AFarshoreCharacter::StaticClass();
    HUDClass = AFarshoreHUD::StaticClass();
    static ConstructorHelpers::FObjectFinder<UStaticMesh> CubeMesh(TEXT("/Engine/BasicShapes/Cube.Cube"));
    static ConstructorHelpers::FObjectFinder<UStaticMesh> SphereMesh(TEXT("/Engine/BasicShapes/Sphere.Sphere"));
    static ConstructorHelpers::FObjectFinder<UMaterialInterface> Material(TEXT("/Game/Farshore/M_FarshoreTint.M_FarshoreTint"));
    Cube = CubeMesh.Object;
    Sphere = SphereMesh.Object;
    BaseMaterial = Material.Object;
    StoneLocations = { FVector(700, -900, 0), FVector(800, 900, 0), FVector(-900, 900, 0) };
    Found.Init(false, 3);
}

void AFarshoreGameMode::BeginPlay()
{
    Super::BeginPlay();
    BuildIsland();
#if WITH_DEV_AUTOMATION_TESTS
    if (FParse::Param(FCommandLine::Get(), TEXT("FarshoreSmoke")) && UGameplayStatics::DoesSaveGameExist(SaveSlot(), 0))
        UGameplayStatics::DeleteGameInSlot(SaveSlot(), 0);
#endif
    GetWorldTimerManager().SetTimerForNextTick(this, &AFarshoreGameMode::InitializePlayer);
#if WITH_DEV_AUTOMATION_TESTS
    if (FParse::Param(FCommandLine::Get(), TEXT("FarshoreSmoke")))
    {
        FTimerHandle Timer;
        GetWorldTimerManager().SetTimer(Timer, this, &AFarshoreGameMode::RunSmokeTest, 2.0f, false);
    }
    if (FParse::Param(FCommandLine::Get(), TEXT("FarshoreCapture")))
    {
        FTimerHandle Timer;
        GetWorldTimerManager().SetTimer(Timer, this, &AFarshoreGameMode::CaptureFrame, 30.0f, false);
    }
#endif
}

void AFarshoreGameMode::InitializePlayer()
{
    ACharacter* Player = UGameplayStatics::GetPlayerCharacter(this, 0);
    if (Player)
    {
        FVector Position = StartPosition;
        if (UGameplayStatics::DoesSaveGameExist(SaveSlot(), 0))
        {
            UFarshoreSave* Save = Cast<UFarshoreSave>(UGameplayStatics::LoadGameFromSlot(SaveSlot(), 0));
            if (Save && Save->Found.Num() == 3 && (!Save->bComplete || !Save->Found.Contains(false)))
            {
                Found = Save->Found;
                bComplete = Save->bComplete;
                if (!Save->Position.ContainsNaN() && FMath::Abs(Save->Position.X) < 1450 && FMath::Abs(Save->Position.Y) < 1450)
                    Position = Save->Position;
            }
            else Message = TEXT("Save could not be loaded. Starting a new journey.");
        }
        Player->SetActorLocation(Position, false, nullptr, ETeleportType::TeleportPhysics);
        for (int32 I = 0; I < StoneMarkers.Num(); ++I)
            if (StoneMarkers[I] && Found[I]) StoneMarkers[I]->SetActorHiddenInGame(true);
    }
    else UE_LOG(LogTemp, Error, TEXT("Farshore could not find the player character."));
}

void AFarshoreGameMode::AddShape(UStaticMesh* Mesh, const FVector& Position, const FVector& Scale,
                                const FLinearColor& Color, bool bSolid)
{
    AStaticMeshActor* Shape = GetWorld()->SpawnActor<AStaticMeshActor>(Position, FRotator::ZeroRotator);
    if (!Shape || !Mesh) return;
    UStaticMeshComponent* Component = Shape->GetStaticMeshComponent();
    Component->SetMobility(EComponentMobility::Movable);
    Component->SetStaticMesh(Mesh);
    Component->SetWorldScale3D(Scale);
    Component->SetCollisionEnabled(bSolid ? ECollisionEnabled::QueryAndPhysics : ECollisionEnabled::NoCollision);
    if (BaseMaterial)
    {
        UMaterialInstanceDynamic* Material = UMaterialInstanceDynamic::Create(BaseMaterial, Component);
        Material->SetVectorParameterValue(TEXT("Color"), Color);
        Component->SetMaterial(0, Material);
    }
}

void AFarshoreGameMode::BuildIsland()
{
    AddShape(Cube, FVector(0, 0, -100), FVector(100, 100, .2), FLinearColor(.19, .40, .47), false);
    AddShape(Cube, FVector(0, 0, -40), FVector(32, 32, .8), FLinearColor(.34, .43, .37), true);
    AddShape(Cube, FVector(0, 0, -5), FVector(31, 31, .1), FLinearColor(.35, .57, .36), true);
    for (float Side : {-1.0f, 1.0f})
    {
        AddShape(Cube, FVector(Side * 1550, 0, 25), FVector(.3, 31, .5), FLinearColor(.38, .45, .36), true);
        AddShape(Cube, FVector(0, Side * 1550, 25), FVector(31, .3, .5), FLinearColor(.38, .45, .36), true);
    }
    AddShape(Cube, FVector(0, 0, 2), FVector(24, 3.2, .04), FLinearColor(.68, .62, .43), false);
    AddShape(Cube, FVector(700, 0, 3), FVector(2.5, 21, .04), FLinearColor(.68, .62, .43), false);
    AddShape(Cube, FVector(0, 0, 160), FVector(2, 2, 3.2), FLinearColor(.55, .60, .51), true);
    AddShape(Cube, FVector(0, 0, 340), FVector(2.4, 2.4, .4), FLinearColor(.59, .32, .25), true);
    FRandomStream Random(7341);
    for (int32 I = 0; I < 45; ++I)
    {
        FVector P(Random.FRandRange(-1400, 1400), Random.FRandRange(-1400, 1400), 0);
        if (FMath::Abs(P.Y) < 240 || FMath::Abs(P.X - 700) < 170 || P.Size2D() < 300 ||
            FVector::Dist2D(P, StartPosition) < 400) continue;
        bool bClear = true;
        for (const FVector& Stone : StoneLocations) if (FVector::Dist2D(P, Stone) < 230) bClear = false;
        if (!bClear) continue;
        AddShape(Cube, P + FVector(0, 0, 110), FVector(.35, .35, 2.2), FLinearColor(.32, .21, .13), true);
        AddShape(Sphere, P + FVector(0, 0, 290), FVector(2.1, 2.1, 2.5), FLinearColor(.22, .43, .26), false);
    }
    for (int32 I = 0; I < StoneLocations.Num(); ++I)
    {
        const FVector P = StoneLocations[I];
        AddShape(Cube, P + FVector(0, 0, 22), FVector(1.7, 1.7, .44), FLinearColor(.55, .60, .51), true);
        AStaticMeshActor* Marker = GetWorld()->SpawnActor<AStaticMeshActor>(P + FVector(0, 0, 90), FRotator::ZeroRotator);
        if (Marker)
        {
            UStaticMeshComponent* Component = Marker->GetStaticMeshComponent();
            Component->SetMobility(EComponentMobility::Movable);
            Component->SetStaticMesh(Sphere);
            Component->SetWorldScale3D(FVector(.6, .6, 1.0));
            Component->SetCollisionEnabled(ECollisionEnabled::NoCollision);
            if (BaseMaterial)
            {
                UMaterialInstanceDynamic* Material = UMaterialInstanceDynamic::Create(BaseMaterial, Component);
                Material->SetVectorParameterValue(TEXT("Color"), I == 0 ? FLinearColor(.7, 1, .6) :
                    (I == 1 ? FLinearColor(1, .8, .45) : FLinearColor(.5, .9, 1)));
                Component->SetMaterial(0, Material);
            }
        }
        StoneMarkers.Add(Marker);
    }
    GetWorld()->SpawnActor<ADirectionalLight>(FVector(0, 0, 1000), FRotator(-55, -30, 0));
    if (ASkyLight* Sky = GetWorld()->SpawnActor<ASkyLight>())
    {
        Sky->GetLightComponent()->SetMobility(EComponentMobility::Movable);
        Sky->GetLightComponent()->SetIntensity(1.0f);
        Sky->GetLightComponent()->RecaptureSky();
    }
}

int32 AFarshoreGameMode::FoundCount() const
{
    int32 Count = 0;
    for (bool bFound : Found) if (bFound) ++Count;
    return Count;
}

void AFarshoreGameMode::Interact()
{
    ACharacter* Player = UGameplayStatics::GetPlayerCharacter(this, 0);
    if (!Player) return;
    const FVector P = Player->GetActorLocation();
    for (int32 I = 0; I < StoneLocations.Num(); ++I)
    {
        if (!Found[I] && FVector::Dist2D(P, StoneLocations[I]) < 220)
        {
            Found[I] = true;
            if (StoneMarkers.IsValidIndex(I) && StoneMarkers[I]) StoneMarkers[I]->SetActorHiddenInGame(true);
            Message = TEXT("A windstone answers. Return its song to the tower.");
            SaveProgress();
            return;
        }
    }
    if (P.Size2D() < 270)
    {
        if (FoundCount() == 3)
        {
            bComplete = true;
            Message = TEXT("The signal returns. Across the water, another light answers.");
            SaveProgress();
        }
        else Message = TEXT("The tower is quiet. Find all three windstones.");
    }
    else Message = TEXT("Explore the island. Find the glowing windstones.");
}

void AFarshoreGameMode::SaveProgress()
{
    UFarshoreSave* Save = Cast<UFarshoreSave>(UGameplayStatics::CreateSaveGameObject(UFarshoreSave::StaticClass()));
    ACharacter* Player = UGameplayStatics::GetPlayerCharacter(this, 0);
    if (!Save || !Player)
    {
        Message = TEXT("Unable to save progress.");
        return;
    }
    Save->Found = Found;
    Save->bComplete = bComplete;
    Save->Position = Player->GetActorLocation();
    if (!UGameplayStatics::SaveGameToSlot(Save, SaveSlot(), 0)) Message = TEXT("Unable to save progress.");
}

#if WITH_DEV_AUTOMATION_TESTS
void AFarshoreGameMode::CaptureFrame()
{
    FScreenshotRequest::RequestScreenshot(FPaths::ProjectSavedDir() / TEXT("FarshoreCapture.png"), false, false);
    FTimerHandle Timer;
    GetWorldTimerManager().SetTimer(Timer, []() { FPlatformMisc::RequestExit(false); }, 3.0f, false);
}

void AFarshoreGameMode::RunSmokeTest()
{
    ACharacter* Player = UGameplayStatics::GetPlayerCharacter(this, 0);
    bool bPassed = Player && StoneMarkers.Num() == 3 && FoundCount() == 0;
    if (bPassed)
    {
        Player->SetActorLocation(FVector(250, 0, 90), false, nullptr, ETeleportType::TeleportPhysics);
        Interact();
        bPassed = !bComplete && FoundCount() == 0;
        for (const FVector& Stone : StoneLocations)
        {
            Player->SetActorLocation(Stone + FVector(200, 0, 90), false, nullptr, ETeleportType::TeleportPhysics);
            Interact();
        }
        bPassed = bPassed && FoundCount() == 3;
        Player->SetActorLocation(FVector(250, 0, 90), false, nullptr, ETeleportType::TeleportPhysics);
        Interact();
        UFarshoreSave* Saved = Cast<UFarshoreSave>(UGameplayStatics::LoadGameFromSlot(SaveSlot(), 0));
        bPassed = bPassed && bComplete && Saved && Saved->bComplete && Saved->Found.Num() == 3 && !Saved->Found.Contains(false);
    }
    if (UGameplayStatics::DoesSaveGameExist(SaveSlot(), 0)) UGameplayStatics::DeleteGameInSlot(SaveSlot(), 0);
    UE_LOG(LogTemp, Display, TEXT("FARSHORE_SMOKE_%s"), bPassed ? TEXT("PASS") : TEXT("FAIL"));
    FPlatformMisc::RequestExit(false);
}
#endif

void AFarshoreHUD::DrawHUD()
{
    Super::DrawHUD();
    if (const AFarshoreGameMode* Game = GetWorld()->GetAuthGameMode<AFarshoreGameMode>())
    {
        DrawText(FString::Printf(TEXT("FARSHORE  /  WINDSTONES %d / 3"), Game->FoundCount()),
                 FLinearColor::White, 28, 24, GEngine->GetSmallFont(), 1.3f);
        DrawText(Game->Message, FLinearColor::White, 28, Canvas->SizeY - 55, GEngine->GetSmallFont(), 1.2f);
    }
}
