# Student Developer Portfolio Starter

This repository contains the starter files for your GitHub Pages portfolio.

Your goal is to replace the placeholder content with a professional introduction, project evidence, development reflections, and working links.

## Required Files

Do not delete or rename these files unless your instructor tells you to do so:

```text
index.html
css/style.css
images/
assets/
```

## Before You Begin

1. Create a new public repository named exactly:

   ```text
   yourusername.github.io
   ```

2. Add these starter files to that repository.
3. Replace `yourusername` with your actual GitHub username.
4. Commit and push your work.
5. Open the repository on GitHub.
6. Go to **Settings → Pages**.
7. Under **Build and deployment**, choose:

   ```text
   Source: Deploy from a branch
   Branch: main
   Folder: /(root)
   ```

8. Save your settings.
9. Visit:

   ```text
   https://yourusername.github.io
   ```

It may take a few minutes for a newly published site to appear.

## Required Portfolio Content

### Home Section

- Your name or professional display name
- A short professional introduction
- A link to your résumé
- A clear button or link to your projects

### About Section

- Your developer story
- Languages you use
- Tools you use
- Your current development focus
- Your professional or career goals

### Project Section

Each featured project must include:

- Project title
- Project screenshot
- Brief project overview
- At least three key features
- Languages and tools used
- A development challenge
- How you solved or approached the challenge
- What you learned
- Repository link
- Demo video link

### Contact Section

Include professional contact methods such as:

- GitHub profile
- LinkedIn profile
- Professional email

Do not publish your home address, personal phone number, student ID, passwords, API keys, or other private information.

## How to Replace an Image

1. Add your image to the `images` folder.
2. Use a clear filename without spaces, such as:

   ```text
   project-screenshot.png
   ```

3. Update the image path in `index.html`:

   ```html
   <img src="images/project-screenshot.png" alt="Screenshot of my project">
   ```

Always write useful alternative text that describes the image.

## How to Add Your Résumé

1. Export your résumé as a PDF.
2. Name it:

   ```text
   student-resume.pdf
   ```

3. Place it inside the `assets` folder.
4. Confirm that the résumé button works on the published site.

## How to Add Another Project

Find one complete block that begins with:

```html
<article class="project-card">
```

Copy the entire block through its closing:

```html
</article>
```

Paste it below the existing project card and replace all placeholder content.

## GitHub Workflow

Complete portfolio updates on your development branch.

```text
dev branch
→ edit portfolio files
→ commit meaningful changes
→ push dev
→ create pull request from dev to main
→ review changes
→ merge pull request
→ verify the published website
```

Do not edit the published `main` branch directly unless your instructor specifically allows it.

## Submission Checklist

Before submitting, confirm that:

- [ ] The published GitHub Pages URL works.
- [ ] Your name appears on the site.
- [ ] No placeholder text remains.
- [ ] No placeholder images remain.
- [ ] Your résumé link works.
- [ ] Every navigation link works.
- [ ] Every project has a screenshot.
- [ ] Every repository link works.
- [ ] Every demo link works.
- [ ] Your site is readable on both desktop and mobile.
- [ ] You removed private information.
- [ ] Your latest changes were merged into `main`.
- [ ] Your published site reflects the latest version.

## What to Submit

```text
Published portfolio URL:
Portfolio repository URL:
Project repository URL:
Demo video URL:
```
