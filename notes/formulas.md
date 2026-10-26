# Receiver conventions and working formulas

Current implementation walkthrough: [新版接收流程阅读文档](../docs/AUTHOR_RECEIVER.zh-CN.md). Some formulas below are general working choices from earlier development; current estimators, scales and saved fields are described in that walkthrough and the MATLAB source.

These formulas define the demo's mathematical conventions. They are not assigned invented paper equation numbers. Source page/section pointers identify the factual or theoretical basis; estimator choices are explicitly marked. Fs below is the **native** 240e6 Hz rate after capture resampling, unless Fs_cap is stated.

Use zero-based sample n, zero-based paper subcarrier k∈{0,…,1023}, and paper slot i∈{0,…,301}. PSS is i=0; the FFT grid contains i=1:301 and MATLAB grid column i. Paper subcarrier k maps to MATLAB row k+1. Define

\[
d[k]=\begin{cases}k&0\le k<512\\k-1024&512\le k<1024,\end{cases}\qquad
f_k=d[k]F_s/N.
\]

Thus Kg={0,1,1022,1023}, Kp={488,…,495,528,…,535}, Kl=K\Kg, and Klnp=Kl\Kp. These frequency conventions and sets come from N01 pp.5,7–8. Klnp has 1004 elements. Sort by d[k] when looking for T-code periodicity; ordinary FFT storage order is different.

Unitary MATLAB-compatible transform pair:

\[
x[n]=\frac1{\sqrt N}\sum_{k=0}^{N-1}X[k]e^{j2\pi kn/N},\qquad
Y[k]=\frac1{\sqrt N}\sum_{n=0}^{N-1}y[n]e^{-j2\pi kn/N}.
\]

Implementation: `x=sqrt(N)*ifft(X,[],1)`, `Y=fft(y,[],1)/sqrt(N)`. Do not insert `fftshift` into this pair. Conventional OFDM CP is `[x(end-Ng+1:end);x]`; remove the first Ng samples before the N-point FFT. PSS uses the special author construction instead. Evidence: N02 `genSss.m`, `genReferenceTemplate.m`; N11 `genOFDM.m`; N01 p.5 transmitted model.

For rate conversion, use Fs_cap=250e6 and Fs/Fs_cap=24/25. Nominal frame support is 302(N+Ng)=318912 native samples followed by 1088 guard samples, totaling 320000. Duration and physical time are invariant under resampling: t=n_cap/Fs_cap=n_native/Fs, after accounting for resampler delay. Frame/sample indices from different rates must not be equated.

Chosen acquisition estimator: with an author-sequence replica r[n] containing PSS+SSS, evaluate

\[
C(q,f)=\sum_{n=0}^{L-1}y[q+n]r^*[n]e^{-j2\pi fn/F_s},\qquad
(\hat q,\hat f)=\arg\max_{q,f}|C(q,f)|.
\]

Positive f is a received positive complex-exponential frequency offset; compensate with `exp(-1j*2*pi*f*n/Fs)`. Report whether q indicates CP/PSS start and whether a fractional delay or grid refinement was used. This simplified lag/CFO search is motivated by N01 p.6 “Coarse frame acquisition”; that paper's physical-beta replica includes time scaling as well as carrier rotation. A peak is not a detection until the chosen threshold/normalization and search limits are specified.

A normalized match diagnostic for one lag is

\[
\gamma=\frac{|\sum y_n r_n^*|^2}{(\sum|y_n|^2)(\sum|r_n|^2)}.
\]

This diagnostic lies in [0,1] by Cauchy–Schwarz for nonzero vectors. It is a demo metric, not a copied paper detection threshold. Protect zero-energy denominators.

Chosen channel estimator: for known nonzero SSS symbols, on Kl only,

\[
\hat H[k]=Y_{i=1}[k]/X_{\rm SSS}[k],\qquad
Z_i[k]=Y_i[k]/\hat H[k].
\]

Optional smoothing/regularization and repeated-frame averaging must be recorded; never divide by the gutter zeros. Guard against small estimated response. This estimate absorbs frame gain, initial phase and SSS timing into H; do not describe it as an independently identified propagation-only channel. N01 pp.6–7 “Channel equalization” motivates SSS division but uses additional normalization and smoothed channel modeling.

Chosen pilot residual-phase estimator at each grid column i=2:301 is

\[
\hat\theta_i=\arg\sum_{k\in K_p}w_k Z_i[k]P_i[k]^*,\qquad
\widetilde Z_i[k]=Z_i[k]e^{-j\hat\theta_i},\quad w_k\ge0.
\]

This only corrects common phase. A residual timing error produces a phase slope across frequency. If fitting both, a useful working model is

\[
\arg(Z_i[k]P_i[k]^*)\simeq\theta_i-2\pi f_k\tau_i,
\qquad
\widetilde Z_i[k]=Z_i[k]e^{-j\hat\theta_i+j2\pi f_k\hat\tau_i}.
\]

Unwrap/model phase carefully: pilot bands are separated by a large gap and the fit can be ambiguous. Fit temporal evolution or constrain small residual delay after acquisition; do not claim unambiguous delay from two pilot bands without verification. N01 pp.6–8 residual models and estimation provide the basis; this weighted pilot fit is an implementation choice, not the paper's full ML estimator.

Known edge pilot symbols are

\[
s_{pik}=\left\lfloor q_{pk}/4^{301-i}\right\rfloor\bmod4,
\qquad P_i[k]=e^{j\pi(s_{pik}+1/2)/2},\quad i=2{:}301,\ k\in K_p.
\]

Read the 150-digit hex string MSB-first, taking two base-4 digits per hex digit. Author `genEdgePilots()` returns A with shape 1024×302 and A(k+1,i+1)=P_i[k]. Assign `gridPilot(:,2:301)=A(:,3:302)`; **do not** compare grid column i with A(:,i). Evidence: N01 p.8 “Edge pilots”; N03 pp.2–3 S3; N02 `genEdgePilots.m`.

Chosen metrics for held-out, known pilots pℓ and their corrected estimates zℓ:

\[
\mathrm{EVM}_{rms}=\sqrt{\frac{\sum_\ell|z_\ell-p_\ell|^2}{\sum_\ell|p_\ell|^2}},
\qquad \mathrm{EVM}_{dB}=20\log_{10}(\mathrm{EVM}_{rms}),
\]
\[
\mathrm{SER}=\frac{\#\{\hat p_\ell\ne p_\ell\}}{L},\qquad
\mathrm{BER}=\frac{\#\{\hat b_r\ne b_r\}}{2L}.
\]

State the actual 4QAM bit labeling used for BER. A demo-selected Gray label is a pilot evaluation convention, not a verified Starlink payload map. EVM computed after an evaluated symbol's own pilot fit is fitted error; evaluate independent held-out pilot rows/symbols to demonstrate predictive correction. Report EVM as a ratio or percent explicitly, and preserve errors rather than clipping to convenient values.

Nearest-constellation hard decisions are `argmin_c abs(z-c)`. N01 p.7 distinguishes QPSK={1,j,−1,−j} from 4QAM=e^(jπ/4)QPSK; p.8 “Information symbol detection” anchors orientation to SSS. Nearest-symbol decisions are not LDPC decoding. Any LLR requires declared bit labeling, noise variance convention and channel scaling; the primary resources do not supply the real payload labeling or FEC parameters.

For empirical low-entropy analysis only, deviations are D_mik=\hat X_mik T_ik^*. T-code periodicity is 60 positions in ascending-frequency Klnp and the circular shift accumulates by 16 positions per actual OFDM symbol interval, including interruptions. Do not measure the period in raw contiguous FFT rows, include pilots, or infer a universal template for arbitrary high-entropy synthetic payload. Evidence: N01 pp.9–10 “Reference template”, “Tessellation codes”.
