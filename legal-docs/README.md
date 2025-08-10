# Nokael Money App - Legal Documents

This repository contains the legal documents for the Nokael Money App, hosted on Cloudflare Pages.

## 📄 Documents

- **Privacy Policy**: [privacy-policy.html](privacy-policy.html)
- **Terms of Service**: [terms-of-service.html](terms-of-service.html)

## 🚀 Deployment

These documents are deployed on Cloudflare Pages and can be accessed at:
- **Privacy Policy**: `https://your-domain.com/privacy-policy.html`
- **Terms of Service**: `https://your-domain.com/terms-of-service.html`

## 🛠️ Setup Instructions

### Option 1: Cloudflare Pages (Recommended)

1. **Create a new GitHub repository** for these legal documents
2. **Push these files** to the repository
3. **Go to Cloudflare Dashboard** → Pages
4. **Create a new project** and connect your GitHub repository
5. **Deploy** - Cloudflare will automatically build and deploy your site

### Option 2: Cloudflare Workers Sites

1. **Install Wrangler CLI**: `npm install -g wrangler`
2. **Login to Cloudflare**: `wrangler login`
3. **Create a new Workers project**: `wrangler init legal-docs`
4. **Upload files**: `wrangler publish`

### Option 3: Cloudflare R2 Storage

1. **Create an R2 bucket** in Cloudflare Dashboard
2. **Upload the HTML files** to the bucket
3. **Configure public access** and custom domain

## 🔗 App Store Integration

Add these URLs to your App Store Connect app:

- **Privacy Policy URL**: `https://your-domain.com/privacy-policy.html`
- **Terms of Service URL**: `https://your-domain.com/terms-of-service.html`

## 📝 Customization

Before deploying, update the following:

1. **Contact Information**: Update email and website URLs
2. **Governing Law**: Replace `[Your Jurisdiction]` with your actual jurisdiction
3. **Domain**: Replace `your-domain.com` with your actual domain
4. **Styling**: Modify colors and branding in the CSS

## 🔒 Security

- All pages are served over HTTPS
- No tracking or analytics included
- Static HTML for maximum security

## 📞 Support

For questions about these legal documents, contact: info@nokael.com
