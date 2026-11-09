#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/HUD.h"
#include "GameFramework/SaveGame.h"
#include "FarshoreGame.generated.h"

class UCameraComponent;
class USpringArmComponent;
class UStaticMesh;
class UStaticMeshComponent;
class UMaterialInterface;

UCLASS()
class FARSHORE_API UFarshoreSave : public USaveGame
{
    GENERATED_BODY()
public:
    UPROPERTY() TArray<bool> Found;
    UPROPERTY() bool bComplete = false;
    UPROPERTY() FVector Position = FVector(-800, -300, 90);
};

UCLASS()
class FARSHORE_API AFarshoreCharacter : public ACharacter
{
    GENERATED_BODY()
public:
    AFarshoreCharacter();
    virtual void Tick(float DeltaSeconds) override;
    virtual void SetupPlayerInputComponent(UInputComponent* Input) override;

private:
    void North(float Value);
    void East(float Value);
    void Interact();
    UPROPERTY() TObjectPtr<USpringArmComponent> CameraArm;
    UPROPERTY() TObjectPtr<UCameraComponent> Camera;
    UPROPERTY() TObjectPtr<UStaticMeshComponent> LeftLeg;
    UPROPERTY() TObjectPtr<UStaticMeshComponent> RightLeg;
    float WalkTime = 0.0f;
};

UCLASS()
class FARSHORE_API AFarshoreHUD : public AHUD
{
    GENERATED_BODY()
public:
    virtual void DrawHUD() override;
};

UCLASS()
class FARSHORE_API AFarshoreGameMode : public AGameModeBase
{
    GENERATED_BODY()
public:
    AFarshoreGameMode();
    virtual void BeginPlay() override;
    void Interact();
    int32 FoundCount() const;
    FString Message = TEXT("Find the three windstones, then return to the tower. E or Space: listen.");
    bool bComplete = false;

private:
    void BuildIsland();
    void SaveProgress();
    UPROPERTY() TObjectPtr<UStaticMesh> Cube;
    UPROPERTY() TObjectPtr<UStaticMesh> Sphere;
    UPROPERTY() TObjectPtr<UMaterialInterface> BaseMaterial;
    UPROPERTY() TArray<TObjectPtr<AActor>> StoneMarkers;
    UPROPERTY() TArray<bool> Found;
    TArray<FVector> StoneLocations;
    void AddShape(UStaticMesh* Mesh, const FVector& Position, const FVector& Scale,
                  const FLinearColor& Color, bool bSolid);
};
