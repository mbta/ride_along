# 2. Initial Architecture

Date: 2024-05-20

## Status

Accepted

## Context

To guide the project, Ride Along needs an initial architecture.

## Decision

Ride Along will be two applications, built and released from the same source
repository (this one). One application will be deployed as a container on-prem,
in order to connect to the ADEPT database. The other will be a web application
in AWS ECS Fargate.

## Consequences

We'll need to be able to start the two different applications, ideally based on
a command-line argument. This way they can share the same configuration.
