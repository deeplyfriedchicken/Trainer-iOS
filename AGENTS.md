# Agent Guidelines

## API / Backend Reference

When you need details about the backend API (endpoints, request/response shapes, auth, etc.), fetch:

https://trainer-crm-six.vercel.app/llms.txt

## Linear Workflow

Follow these steps every time you work on a Linear ticket:

1. **Move to In Progress** — as soon as you read a Linear issue and accept the work, update the ticket status to `In Progress`.
2. **Comment with task list** — once you understand what needs to be done, post a comment on the ticket listing every task as an unchecked Markdown checklist (`- [ ] task`).
3. **Check off tasks as you go** — after completing each task, update that comment to mark the item checked (`- [x] task`). Keep the checklist current so progress is visible in Linear.
4. **Wrap up** — when all tasks are done, post a final comment summarising all the work completed, then move the ticket status to `In Review`.

## Ticket Updates

The ticket **description is the source of truth**. When requirements change mid-ticket:
- Update the description to reflect the current state.
- Leave a comment explaining what changed and why (for audit trail).

Always check comments on a ticket before starting work — they may contain corrections or updates that supersede the original description.

## Push Notifications (FCM)

The iOS app receives push notifications via Firebase Cloud Messaging (FCM) → APNs when trainers receive new client messages.

### Architecture

- `AppDelegate.swift` — configures Firebase, requests notification permission, receives FCM token via `MessagingDelegate`
- `AppStore.registerFCMToken()` — explicitly fetches and registers the FCM token on every login (called from `checkAuth()`); do not rely solely on the delegate callback as it doesn't always fire on reinstall
- `APIClient.registerPushToken()` / `deletePushToken()` — POST/DELETE to `/api/push-tokens` on the backend
- Token is deleted from the server on `signOut()` so the trainer stops receiving notifications after logout

### Critical gotchas

**Use a universal APNs key, not a topic-specific one.** In Apple Developer Portal, when creating the APNs key, leave topic restrictions empty. Firebase has known delivery failures with "Topic specific" keys even when the bundle ID matches.

**Both the Apple key and Firebase upload must be set to Production.** APNs auth keys have a production/sandbox environment. TestFlight and App Store builds use production APNs — both the key itself and the Firebase upload setting must be Production.

**Do not test FCM delivery from an Xcode debug build.** Debug builds use the APNs sandbox endpoint. FCM will return success but the notification will never arrive on device. Always test via TestFlight.

**`didReceiveRegistrationToken` is unreliable on reinstall.** The delegate callback may not fire when the app is reinstalled or a new build is installed. The explicit `Messaging.messaging().token { }` call in `registerFCMToken()` ensures the token is always current.

### Testing

1. Install the app via TestFlight (not Xcode)
2. Launch the app — notification permission dialog appears on first launch
3. Grant permission
4. Have a client send a message from the PWA
5. The trainer should receive a banner notification within seconds
