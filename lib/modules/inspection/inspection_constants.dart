const double siteVerificationDistanceThresholdMeters = 30.0;

/// Shared reliability gates; pure values also used by explanatory UI.
const double kReliableFixMaxAccuracyMeters = 25;
const Duration kReliableFixMaxAge = Duration(seconds: 15);
const Duration kReliableFixFutureSkew = Duration(seconds: 2);

const defaultSiteCondition = {
  'Structure matches declared use': false,
  'Setback distances compliant': false,
};
const defaultZoningObservations = {
  'Accessibility & road frontage': false,
  'Surrounding developments noted': false,
  'Signage / commercial activity present': false,
};
