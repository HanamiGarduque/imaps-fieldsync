# iMAPS:FieldSync

## What is iMAPS:FieldSync?
A mobile application designed for municipal planning and development office (MPDO) inspectors to conduct zoning inspections on-site efficiently.

## Main Purpose and Target Users
iMAPS:FieldSync aims to facilitate the inspection process for inspectors, providing tools for management and verification of tasks, ensuring adherence to zoning regulations.

## Core Features
- **User Authentication**: Secure login via email/passcode with options for biometric access.
- **Home Dashboard**: Quick view of assigned tasks and notifications.
- **My Tasks**: Manage and categorize tasks based on their status (pending, ongoing, completed).
- **Inspection Workflow**: A structured 6-step process for detailed inspections.
- **Offline Functionality**: Ability to work without internet access, storing information locally until syncing.
- **Sync Center**: Handles the automatic synchronization of task data when connectivity is available.

## Technology/Platform Stack
- Flutter framework
- Dart programming language
- Supabase for backend services

## Login and Authentication
- **Email/Passcode**: Inspectors log in using registered email and password.
- **Biometric Authentication**: Available after initial login to enhance security and streamline access.
- **Forgot Password**: An option to reset the password if forgotten.
- **Terms & Privacy**: Users must acknowledge the terms and privacy policies upon account creation.
- **Online/Offline Login**: Options to log in both online and offline based on previously cached sessions.

## Home Dashboard
Inspectors are presented with a clean and concise dashboard displaying upcoming tasks and connectivity status.

## My Tasks
- **Task Categories**: Organized into Pending, Ongoing, and Completed sections.
- **Status vs Priority Colors**: Blue for pending, yellow for high priority, red for urgent tasks, and green for completed.
- **Scheduling/Rescheduling**: Options to set and modify inspection dates.

## Inspection Workflow
1. **Step 1 - Site Verification**: Navigate to the targeted inspection site.
2. **Step 2 - GPS Verification**: Verify that you are within 30 meters of the site using GPS.
3. **Step 3 - Photos**: Capture geotagged inspection photos without a fixed 10-photo cap in the app workflow.
4. **Step 4 - Checklist**: Complete zoning compliance checklist.
5. **Step 5 - Findings**: Document observations and discrepancies.
6. **Step 6 - Review & Submit**: Finalize and submit inspection findings.

## Completed Inspections and Rework
Completed inspections can be reviewed, and any necessary rework can be initiated based on findings.

## Offline / Local-First → Cloud-Later Behavior
Tasks can be worked on without internet access, with all data saved locally until a connection is re-established for syncing.

## Sync Center and Automatic Synchronization
Any pending submissions are managed within the Sync Center to ensure data consistency across devices.

## Profile
Users can manage their profile information and app settings from within the app.

## Security & Protection
Comprehensive measures are in place to secure user data and inspection information.

## Diagnostics & Support
Provides users with access to help resources and troubleshooting information.

## Help & FAQ
A section that includes common questions and answers regarding the application usage.

## Privacy/Security Architecture
The application utilizes secure protocols to ensure personal information and inspection data remain confidential and secure.

## Current App Version Handling
Inspectors are always notified of the current app version and whether updates are available.

## Setup/Run/Build Instructions
For more information regarding the setup and running of the application, refer to the Flutter documentation for initial project setup guidelines.
## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
