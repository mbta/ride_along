# 3. Communicate via MQ

Date: 2024-05-30

## Status

Accepted

## Context

The two halves of Ride Along (on-prem and cloud) need to communicate data. 

## Decision

The two halves will connect to the MQ broker currently used by the API and Concentrate, and communicate via queues there.

## Consequences

- This makes local development easier, as we can easily run an MQ broker via Docker Compose
- Deployment is slightly more complicated, as we need to create a secret for the MQ password rather than IAM
