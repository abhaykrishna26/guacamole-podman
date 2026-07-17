# OIDC SSO Setup Guide

## 📌 Prerequisites
- A running **Apache Guacamole** instance  
- **Microsoft Entra ID (Azure AD)** tenant with admin access  
- **SSL/TLS enabled** on Guacamole (OIDC requires HTTPS)

> ⚠️ **Note:** OIDC handles *authentication only*, not permissions. Authorization is still controlled in Guacamole.

---

## 1️⃣ Create an App Registration in Entra ID

### a) Register the application

Navigate to:

**Azure Portal → Azure Active Directory → App registrations → New registration**

Fill in the following values:

| Field | Value |
|-------|--------|
| **Name** | Example: `Guacamole-SSO` |
| **Supported account types** | *Accounts in this organizational directory only* |
| **Redirect URI (Web)** | `https://<guacamole-public-url>/` |

After creating the app, note:

- **Application (client) ID** → `oidc-client-id`  
- **Directory (tenant) ID** → `oidc-tenant-id`

---

### b) Enable ID Tokens

Navigate:

**Manage → Authentication**

Enable:

- ✔ **ID tokens (used for implicit and hybrid flows)**

---

## 2️⃣ Create Client Secret

Navigate:

**Manage → Certificates & secrets → New client secret**

- Add description and expiry  
- Click **Add**  
- Copy the **client secret value** → `oidc-client-secret`

> ⚠️ The secret value is shown **only once**.

---

## 3️⃣ Configure API Permissions

Navigate:

**Manage → API permissions → Add a permission → Microsoft Graph → Delegated permissions**

Add the following permissions:

| Permission | Purpose |
|-----------|----------|
| `openid`  | Required to sign users in |
| `profile` | Required for profile info |
| `email`   | Required for email claim |

Click:

**✔ Grant admin consent**

---

## 4️⃣ Enable Group Claims

Navigate:

**Manage → Token configuration → Add group claim**

Select:

- ✔ **Security groups**  
- ✔ **Groups assigned to the application** (recommended for least privilege)

Customize token format:

- ✔ **Group ID** *(or sAMAccountName depending on mapping strategy)*

Click **Save**.

This ensures **group memberships are included in the ID token**.

---

## 5️⃣ Restrict Access to Guacamole on the Enterprise Application tab

Navigate:

**Entra ID → Enterprise applications → Select your app (e.g., `Guacamole-SSO`)**

### a) Require user/group assignment

Navigate:

**Manage → Properties**

Set:

- **Assignment required? → Yes**  
- Save (💾)

### b) Assign users / groups

Navigate:

**Manage → Users and groups → Add user/group**

Select your group, e.g.:

- `guacamole_users`

Assign and save.

Only assigned users/groups are allowed to access Guacamole via SSO.

---
