# Project rules

Preserve original IQ and source archives; no credentials in tracked files/logs.
Native Linux MATLAB performs DSP. DSH online model alone owns code claimed as dsh_agent; Codex baselines are labelled codex_baseline.
Document provider only: knowledge_mode=documents, kg_enabled=false.
The deployed DSH research agent may write runs/<run_id>/agent-code only through versioning tools; evaluator, truth and frozen thresholds are protected from DSH and hashed. Codex CLI and its explicitly delegated matlab_baseline engineering agent are authorized to implement and fix the independent evaluator before config/evaluator_lock.json is created. Never lower config/evaluation.json thresholds in response to a failed validation. After the lock is created, changes require an explicit new evaluation version and revalidation; DSH cannot change it. sliceInfo TOAs are evaluation annotations, never acquisition inputs.
Missing FEC H, codeblock boundaries, bit map and scrambler remain explicit unknowns. Constellation decisions do not imply payload recovery.
Use separate MATLAB paths for different author source packages.
