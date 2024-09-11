# 5. Use XGBoost for ETA Predictions

Date: 2024-08-29

## Status

Accepted

## Context

We want to show riders estimated time of pick-up (ETA) values they can rely on.

## Decision

We'll use an XGBoost (eXtreme Gradient Boosted tree) model (via EXGBoost/XGBoost) trained on actual arrival data, with the following features (all times in seconds):

- Route ID
- Duration as calculated by OpenRouteService
- Duration as calculated by the promise time
- Duration as calculated by the pick time
- Time of day (number of seconds before/after noon on the service day)
- Day of week (ISO weekday, Monday as 1)
- Latitude/longitude of the pick-up location
- Order of the pickup during the day
- Vehicle speed (not clear what unit)

As the model is currently small (~500K) we'll include it directly in the Git repo.

As of this ADR, the accuracy (calculated using the buckets used by Prediction Analyzer: https://www.notion.so/mbta-downtown-crossing/Prediction-Accuracy-Metric-Use-Cases-d6836c2503c849fc9ac44b9555a89639) of the ADEPT ETAs is 33%. By using the model, we can increase this accuracy to 48%.

## Consequences

If the model becomes bigger, it may become challenging to include it in the Git repository, requiring a switch to Git-LFS (Large File Storage) for the trained model, or storing it outside the repository entirely (S3).

The RideAlong ETAs will likely be different from the ETAs received via text messages, as well as the values seen in ADEPT. We are working on providing access to RideAlong to the TRAC staff so that they can look up the RideAlong ETA (as well as the vehicle location) if riders call in.

In the future, we may be able to include additional data in the model as well.

## Alternative approaches

We looked at using a feed-forward neural network, but the accuracy was worse and
training is more complicated (features needed to be normalized).
