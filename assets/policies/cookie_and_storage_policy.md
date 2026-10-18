# Cookie & Storage Policy

**iMAPS: An Intelligent Geospatial Analytics System + FieldSync Mobile App**

**Document status:** DRAFT v0.9 — MPDO/DPO review required; not yet effective
**Prepared:** October 18, 2026
**Date shown in existing FieldSync app (legacy reference only):** September 7, 2026
**New policy effective date:** Pending official approval

> **DRAFT — FOR REVIEW ONLY.** This is proposed public-facing wording, not an approved municipal notice. Confirm contacts, technical claims, and deployment facts before publication.

---

## 1. Scope: Web Cookies and Mobile Storage

This policy describes how the iMAPS internal web system and FieldSync mobile app may use browser cookies, web storage, device-local storage, and connected servers. Browser cookies and mobile offline records are different technologies; FieldSync does not need to use browser cookies merely because the iMAPS web system does. Any separate public status portal should publish a matching notice based on its actual implementation.

## 2. Essential Web Session and Security Storage

The Laravel-based iMAPS web system may use session-related cookies and anti-forgery tokens to maintain an authenticated session and protect requests. The actual cookie names, scope, expiration, SameSite settings, Secure/HttpOnly flags, and whether sessions are stored server-side must be verified from the deployed configuration. Necessary storage enables authorized workflows; users may be unable to sign in or use protected features if their browser blocks it.

## 3. Web Preferences, Caches, and Reports

Depending on implemented features, the browser may store non-essential preferences (for example, visual or map-view choices) and temporarily cache downloaded resources. An earlier internal assessment also flagged forecast outputs saved to browser localStorage without an expiry; the team must confirm whether that behavior still exists, what information it contains, and whether it should be moved to server-controlled records or given an expiration. No claim is made that all cached information is automatically removed at logout.

## 4. FieldSync Offline Storage

FieldSync may keep inspection assignments, draft forms, GPS readings, geotagged media references, and a synchronization queue on the device so field work can continue during connectivity interruptions. When service returns, the app may attempt to upload pending items to the connected backend or synchronization service. A successful upload does not automatically prove that local copies, device backups, or cached media were erased. The product team must document actual file locations, storage protections, queue cleanup, retry behavior, and the user-facing sync status.

## 5. Authentication and Other Device Data

FieldSync may maintain a session token or similar credential needed for signed-in users. Mobile operating systems and application libraries may also store preferences and temporary media files. Whether credentials are stored in protected device facilities, whether offline records are encrypted at rest, and whether app removal deletes all related copies or cloud backups must be tested. Do not store passwords or sensitive authentication secrets in plain text.

## 6. Maps and External Resources

When users display basemaps or other externally hosted map resources, their browser or device may send ordinary technical requests to the map provider, potentially including an IP address and network/device metadata. The iMAPS manuscript identifies OpenStreetMap and Esri basemaps used with Leaflet and MapLibre; exact provider endpoints, attribution, analytics, cookies, and external requests must be reviewed against the production configuration and respective provider notices.

## 7. Analytics, Advertising, and Optional Tracking

The project materials reviewed do not establish the deployment of advertising cookies, cross-site marketing trackers, or optional behavioral analytics. They must not be described as installed—or definitively absent—without an inventory of production scripts and mobile SDKs. If non-essential tracking is introduced, the responsible office must update this policy and implement any legally required choice and notice mechanisms before activation.

## 8. How Users Can Manage Storage

Web users can manage cookies and local website data through their browser settings, but deleting essential session data can sign them out. FieldSync users can manage app permissions through operating-system settings and should use the app’s intended synchronization workflow before clearing app data or uninstalling it; otherwise, unsent inspection drafts may be lost. Municipal device administrators should provide an approved process for lost devices, account revocation, and secure disposal. Privacy and retention requests should go through the designated DPO.

## 9. Data Retention and Updates

Storage lifetimes vary by record type, device state, server configuration, backup practice, and legal records-retention duties. The final published policy must specify, or link to a schedule for, actual session expiration, offline draft cleanup, audit-log retention, application/inspection record retention, and third-party storage practices. Review this policy whenever the app adds an SDK, changes its sync design, or alters cookies or storage settings.

## 10. Contact and Version

Responsible office: Municipal Planning and Development Office (MPDO), Municipality of Rosario, Batangas. Official DPO/privacy contact: __________. Draft version: 0.9. Effective date: Pending official approval. Users may request clarification about storage, cookies, or data rights through the verified contact channel published with the final policy.

---

**Notice:** Draft v0.9. Approval and effective date remain pending. Contact names and details are intentionally blank until verified.
