# Environment Setup for Braid App

To keep the application secure and prevent Google Cloud Service Account credentials from leaking on GitHub, we use environment variables.

## Getting Push Notifications to Work Locally

If you clone or download this repository, push notifications will not work out of the box because the FCM private key is omitted from the codebase.

To fix this, you need to create an environment file.

### Step 1: Create the `.env` file
In the root directory of the `bsgc_app` project (the same folder as this file), you will see a file named `.env.example`.
Copy this file and rename it to `.env`:

```bash
# On Windows
copy .env.example .env

# On Mac/Linux
cp .env.example .env
```

### Step 2: Add your Firebase Cloud Messaging Private Key
Open the new `.env` file in VS Code or any text editor. It looks like this:
```env
FCM_PRIVATE_KEY_ID="YOUR_PRIVATE_KEY_ID_HERE"
FCM_PRIVATE_KEY="YOUR_PRIVATE_KEY_HERE"
```

Replace `"YOUR_PRIVATE_KEY_HERE"` with the actual private key from your Firebase Service Account JSON file. 
*Note: Make sure your private key is wrapped in quotes and preserves the `\n` characters just as it appears in the JSON.*

### Security Notice
The `.env` file is already added to `.gitignore`. **Never commit your `.env` file to version control.** If you ever accidentally commit a private key to GitHub, you should immediately revoke it in the Google Cloud Console and generate a new one.
