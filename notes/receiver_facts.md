# Verified receiver facts and limits

Source IDs resolve in [source_index.json](source_index.json). Page numbers below are one-based PDF physical pages, preserved separately in `sources/page_text`; they are not viewer zero-based indices. `verified` means checked against the local, manifest-validated primary source. Receiver design choices are labeled separately.

| Quantity | Verified value and units | Primary evidence |
|---|---|---|
| Native information/sample rate | 240,000,000 Hz | P01 p.11 Table II; N01 p.5 “Transmitted signal model”; N02 `starlinkConstants.m` |
| Raw exemplar capture rate | 250,000,000 complex samples/s | N02_RAW `exemplar250-257.json`, `README.txt`; N01 p.5 “Received signal model” |
| FFT and CP lengths | N=1024, Ng=32 native samples | P01 p.11 Table II; N02 `genSss.m` |
| Subcarrier spacing | 234,375 Hz | P01 p.11 Table II; 240e6/1024 |
| Useful/CP/full symbol duration | 4.266666667 / 0.133333333 / 4.4 µs | P01 p.11 Table II |
| Frame clock | 750 slots/s, Tf=1/750 s | P01 p.11 Table II; N01 p.4 “Signal model” |
| Occupied slots | 302: PSS i=0, SSS i=1, then i=2:301 | N01 p.5 “Transmitted signal model”; P01 p.12 Fig.6 |
| Native occupied/frame-period samples | 318,912 / 320,000 | Derived from the preceding verified values |
| Frame guard | 1088 native samples, 4.533333333 µs | P01 p.11 Table II; N02 `starlinkConstants.m` |
| FFT grid | 1024×301; column 1 is SSS, columns 2:301 are i=2:301 | N01 p.8 Fig.5; N02 exemplar guide |
| Capture size and encoding | 12,500,000 complex samples, 50,000,000 bytes; interleaved sc16 IQ | N02_RAW README/metadata; N02_BIN validated length/hash |
| Capture tuning | 12,075,117,197.166800 Hz, channel 6 metadata | N02_RAW `exemplar250-257.json`, `sliceInfo.json` |

The capture rate is a receiver setting, not the waveform's native rate or the 250 MHz channel spacing. Resample 250→240 MHz with rational ratio 24/25 before interpreting a 32-sample CP or 1056-sample OFDM interval. In 250 MHz capture samples the nominal full symbol spans 1100 samples, but the useful/CP lengths are not both integers. Anti-alias filtering and resampler delay are implementation details that must be included in reported timing. N01 p.5 explicitly states that its 250 Msps recordings were resampled to Fs before subsequent operations.

At 240 MHz a maximum-rate frame period is 320,000 samples. This does not mean all 750 slots/s are occupied: N01 pp.4–5 distinguish the frame clock from transmitted-frame occurrence, and P01 pp.12–13 show intermittent frames. Raw slice metadata lists TOAs from eight exemplar frame indices; the last frame starts around 49.833 ms and is incomplete in the 50 ms file (`nWhole=7`). These metadata TOAs are evaluation aids, not acquisition outputs to feed the receiver.

FFT indexing is unshifted throughout processing: paper k=0:1023 maps to MATLAB row k+1, with signed frequency index d[k]=k for k<512 and k−1024 otherwise. `fftshift` is only a display/order operation when explicitly requested. The gutter is paper k={0,1,1022,1023}, MATLAB rows {1,2,1023,1024}. It is not a four-bin window centered on row 513 of an unshifted FFT. Under MATLAB `fftshift`, these bins become rows 511:514. Evidence: N01 p.5 “Transmitted signal model”; N02 `genReferenceTemplate.m`; N11 `genOFDM.m`.

The PSS is a native time-domain sequence, not an ordinary QAM-bearing FFT-grid column. N02 `genPss.m` generates the 7-stage Fibonacci LFSR, eight 128-sample segments, an inverted first segment, and an inverted 32-sample CP. Use the validated author implementation as sequence evidence; do not replace it with a randomly chosen m-sequence or a standard OFDM CP. P01 pp.10–11 disclose the PSS and SSS, and N02 `genSss.m` uses `sqrt(1024)*ifft(sssVecFull)` with a conventional 32-sample CP. Its useful-symbol energy is 1020 due to the four nulled gutter bins; the PSS useful-symbol energy is 1024. This slight energy difference is intentional.

Edge pilots use paper subcarrier indices k=488:495 and 528:535 (MATLAB rows 489:496 and 529:536). There are 16 pilots in every ordinary data symbol i=2:301, using 4QAM rotations exp(jπ(spik+1/2)/2), with spik from the 150-hex-digit qpk sequences in N03 pp.2–3, Supplementary Note S3. N01 p.8 “Edge pilots” gives the locations and formula. The author generator returns 1024×302, including zero columns for PSS and SSS: **author columns 3:302 must be assigned to receiver grid columns 2:301**. Row or column shifts change the expected pilot sequence and invalidate EVM/BER comparisons.

The SSS spans all loaded subcarriers and provides a known channel-estimation reference. N01 pp.6–7 “Channel equalization” estimates a frequency-dependent response from the SSS, smooths it, and separates a frame complex gain. Its pp.7–8 “Residual synchronization parameter estimation” estimate per-symbol phase/delay and fit their time evolution; the alternative method marginalizes over constellation points. A practical demo can use SSS least squares and known-pilot residual phase/timing tracking, but it must identify that as its chosen estimator. It is not a complete reproduction of the paper's multi-stage ML procedure.

The paper distinguishes carrier-frequency offset and sample-frequency offset because the carrier and sample clocks need not be identical (N01 pp.4–6 “Clock models”, “Received signal model”). Physical Doppler beta has fD=−beta*Fc under its velocity convention; a demo CFO correction of exp(−j2π*fhat*n/Fs) assumes the received samples contain exp(+j2π*fhat*n/Fs). Keep the sign convention explicit. A single frequency rotation does not correct sample-rate drift.

The low-entropy result applies to observed QPSK regions and their relationship to a supplied reference template, not every arbitrary payload. N01 pp.9–11 describe BPSK deviations, 60-bit T-codes, and 16-position shifts in the ascending-frequency list of **loaded, non-pilot** subcarriers. That list contains 1004 bins; it excludes gutter and pilots before periodicity is measured. Patterns can continue across non-QPSK interruptions with the shift accumulated by symbol index. N03 p.2 Table S1 records the observed corpus, and N01 p.11 reports T-codes in 530 of the 1009 exemplar frames. Treat extrapolation to all satellites or future releases as the authors' inference, not universal receiver truth. No large decoded-frame MAT dataset is needed or downloaded for this offline raw-IQ demo.

“Hard-decoded” in N01 and N02 means nearest-constellation symbol decisions. The supplied papers/code do not specify a usable full payload FEC contract: no actual parity-check matrix H, LDPC block length/rate, bit-to-symbol labeling/interleaving, or complete scrambler polynomial/state/mapping and framing are provided. N01 pp.10–11 explicitly conjecture a scrambler/LDPC explanation for the tessellation; N01 p.9 states that header semantics are not interpreted. A demo may report pilot error, EVM, constellation decisions, and synchronization quality. It cannot claim recovered network payload bits, a successful Starlink LDPC decoder, or user traffic reconstruction from these sources.

The synthetic transmitter may model observed constants and known sequences plus invented test payload symbols. Label generated IQ as synthetic, and do not present it as a recovered Starlink payload or as the paper's complete transmitter. N11 is an archived public simulator reference at commit `5de898badd03f6a8b3c7d5196b9b31d4039263ed`, not a normative current specification.

Source anomalies and code discrepancies are preserved in [source_review.json](../reports/source_review.json). In particular, the original raw metadata `unix_time="17375117563"` has an anomalous 11-digit value inconsistent with the documented 2025 capture epoch. Do not silently divide it, replace it, or treat it as a trusted timestamp. The raw README also lists `readIQslice.m`, which is absent from the supplied ZIP. Neither anomaly changes the verified sample rate, BIN size, or hash.
