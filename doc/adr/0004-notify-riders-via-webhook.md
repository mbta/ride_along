# 4. Notify Riders via Webhook

Date: 2024-08-09

## Status

Accepted

## Context

RideAlong needs to send a text message to riders when their secure link is valid.

## Decision

The existing text messages are handled by a vendor, who has agreed to accept a
webhook when RideAlong wants to send a message. The body of the webhook is:

- time of notification (RFC3339 timestamp in local time)
- trip ID (int)
- route ID (int)
- client ID (int)
- promise time (RFC3339 timestamp in local time)
- ETA (RFC3339 timestamp in local time)
- trip status (string, all-caps)
- secure URL (string)
- notification ID (bigint, always greater than 101,010,001)

Additionally, a message signature is included as the `x-signature-256` HTTP
header.

In order to create a unique notification ID without needing to store them in a
database, we'll hash together features of the trip which don't change into a
unique number. We'll also include the date of the trip as a prefix, to ensure
that we don't have overlapping notification IDs between different days and that
the notification ID is greater than the values used by ADEPT.

The webhook will be delivered over HTTPS, and the contents will be signed with
an HMAC-SHA256 signature. This prevents:

- attackers eavesdropping on the webhook
- attackers sending fake notifications

After receiving the webhook, the vendor will:

1. validate the signature, and reject the webhook if the signature doesn't match
1. if the notification ID has already been sent, stop processing
1. send a notification
1. store the notification ID for future de-duplication

## Consequences

This allows us to notify riders with the same number and process that they're
used to. In the future, the vendor may be able to use our own internally
generated ETAs by storing the values received in the webhook, or by making an
API call (authenticated separately) to RideAlong.
