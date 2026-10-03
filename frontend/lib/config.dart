/// Where the FastAPI backend lives. Everything runs on this machine — no
/// cloud, no external hosts.
const String kApiBaseUrl = 'http://localhost:8000';

/// THE ONE-LINE FLIP.
///
/// `true`  -> UI reads from [MockOmalyApi] (hardcoded data, no server needed).
/// `false` -> UI reads from the real backend at [kApiBaseUrl].
///
/// If a teammate's endpoint breaks mid-demo, flip this back to `true`.
const bool kUseMockApi = false;
