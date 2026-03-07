---
name: gws-calendar
description: "View and manage Google Calendar events. Check today's schedule, upcoming meetings, and calendar availability."
---

# Google Calendar via gws CLI

> See `../gws-shared/SKILL.md` for auth, global flags, and CLI syntax.

```bash
gws calendar <resource> <method> [flags]
```

## Quick Commands

### Agenda (upcoming events across all calendars)

```bash
gws calendar +agenda
gws calendar +agenda --today
gws calendar +agenda --tomorrow
gws calendar +agenda --week
gws calendar +agenda --days 3
gws calendar +agenda --days 3 --calendar 'Work'
gws calendar +agenda --format table
```

### List calendars

```bash
gws calendar calendarList list
```

### Today's events

```bash
gws calendar events list --params '{
  "calendarId": "primary",
  "timeMin": "2026-03-06T00:00:00Z",
  "timeMax": "2026-03-07T00:00:00Z",
  "singleEvents": true,
  "orderBy": "startTime"
}'
```

### Search events

```bash
gws calendar events list --params '{
  "calendarId": "primary",
  "q": "standup",
  "singleEvents": true,
  "orderBy": "startTime",
  "maxResults": 10
}'
```

### Get single event

```bash
gws calendar events get --params '{"calendarId": "primary", "eventId": "EVENT_ID"}'
```

### Free/busy query

```bash
gws calendar freebusy query --json '{
  "timeMin": "2026-03-06T00:00:00Z",
  "timeMax": "2026-03-07T00:00:00Z",
  "items": [{"id": "primary"}]
}'
```

### Create event (quick add)

```bash
gws calendar events quickAdd --params '{"calendarId": "primary", "text": "Lunch with Alice tomorrow at noon"}'
```

## Event Properties

Key fields in event responses:
- **summary**: Event title
- **start.dateTime** / **start.date**: Start time (dateTime for timed events, date for all-day)
- **end.dateTime** / **end.date**: End time
- **location**: Meeting location or video link
- **description**: Event description
- **attendees**: Array of attendee objects with email, responseStatus
- **hangoutLink**: Google Meet link if present
- **htmlLink**: Link to view event in Google Calendar

## Parameters

| Parameter | Description |
|-----------|-------------|
| `timeMin` | Lower bound (exclusive) for event end time (RFC3339) |
| `timeMax` | Upper bound (exclusive) for event start time (RFC3339) |
| `singleEvents` | Expand recurring events into instances (set to `true`) |
| `orderBy` | `startTime` (requires singleEvents=true) or `updated` |
| `maxResults` | Max events to return (default 250) |
| `q` | Free text search terms |

## Notes

- The `+agenda` helper is read-only and never modifies events
- Times must be in RFC3339 format
- Use `singleEvents=true` to expand recurring events
- `primary` refers to the user's primary calendar; use calendar ID for others
- All-day events use `start.date` instead of `start.dateTime`
