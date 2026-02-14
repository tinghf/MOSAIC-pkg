# Concrete Example: Multi-Country Coupling

## Scenario: Cholera Outbreak in East Africa (ETH, KEN, SOM)

### Setup

**Countries:**
- **Ethiopia (ETH)**: Pop = 112M, Coordinates = (9.1°N, 40.5°E)
- **Kenya (KEN)**: Pop = 51M, Coordinates = (-0.0°, 37.9°E)
- **Somalia (SOM)**: Pop = 15M, Coordinates = (5.2°N, 46.2°E)

**Mobility Parameters** (from empirical data):
```r
tau <- c(ETH = 7.9e-6, KEN = 4.9e-5, SOM = 2.3e-5)
mobility_omega <- 0.613
mobility_gamma <- 1.361
```

**Distances** (great-circle, km):
```
     ETH   KEN   SOM
ETH   0    760   950
KEN  760    0    680
SOM  950   680    0
```

---

### Step 1: Compute Diffusion Matrix π_{ij}

Using the gravity model formula for each origin → destination pair:

**From Ethiopia (ETH):**
```r
# Numerators (N_j^omega × d_ij^(-gamma)):
numerator[KEN] = 51,000,000^0.613 × 760^(-1.361) = 794 × 0.00056 = 0.445
numerator[SOM] = 15,000,000^0.613 × 950^(-1.361) = 398 × 0.00036 = 0.143

# Total: 0.445 + 0.143 = 0.588

# Probabilities (destination given departure from ETH):
π[ETH→KEN] = 0.445 / 0.588 = 0.757  (76% of Ethiopian travelers go to Kenya)
π[ETH→SOM] = 0.143 / 0.588 = 0.243  (24% go to Somalia)
```

**From Kenya (KEN):**
```r
numerator[ETH] = 112,000,000^0.613 × 760^(-1.361) = 1413 × 0.00056 = 0.791
numerator[SOM] = 15,000,000^0.613 × 680^(-1.361) = 398 × 0.00063 = 0.251

π[KEN→ETH] = 0.791 / 1.042 = 0.759  (76% to Ethiopia)
π[KEN→SOM] = 0.251 / 1.042 = 0.241  (24% to Somalia)
```

**From Somalia (SOM):**
```r
numerator[ETH] = 112,000,000^0.613 × 950^(-1.361) = 1413 × 0.00036 = 0.509
numerator[KEN] = 51,000,000^0.613 × 680^(-1.361) = 794 × 0.00063 = 0.500

π[SOM→ETH] = 0.509 / 1.009 = 0.504  (50% to Ethiopia)
π[SOM→KEN] = 0.500 / 1.009 = 0.496  (50% to Kenya)
```

**Full Diffusion Matrix:**
```
        ETH    KEN    SOM
ETH     NA    0.757  0.243
KEN   0.759    NA    0.241
SOM   0.504  0.496    NA
```

**Interpretation:**
- Ethiopian travelers mostly go to Kenya (closer, more connected)
- Kenyan travelers split between Ethiopia (larger population) and Somalia
- Somali travelers split evenly between neighbors

---

### Step 2: Outbreak Scenario - Kenya Has Active Outbreak

**Epidemic State on Day t:**
```
Infected cases (I₁ + I₂):
  ETH: 50 cases
  KEN: 5,000 cases  ← OUTBREAK
  SOM: 100 cases

Susceptibles (S + V_sus):
  ETH: 110,000,000
  KEN: 48,000,000
  SOM: 14,800,000
```

---

### Step 3: Calculate Gravity-Weighted Prevalence for Each Country

**For Ethiopia (receiving infections):**
```
ȳ_ETH = [
  (1 - τ_ETH) × infected_ETH +           # Local contribution
  τ_KEN × π[KEN→ETH] × infected_KEN +    # Import from Kenya
  τ_SOM × π[SOM→ETH] × infected_SOM      # Import from Somalia
] / total_population

= [
  (1 - 7.9e-6) × 50 +                    # ≈ 50 (almost all local)
  4.9e-5 × 0.759 × 5000 +                # = 0.186 (Kenya export)
  2.3e-5 × 0.504 × 100                   # = 0.001 (Somalia export)
] / 178,000,000

= (50 + 0.186 + 0.001) / 178,000,000
= 2.82 × 10⁻⁷
```

**For Kenya (has outbreak):**
```
ȳ_KEN = [
  (1 - 4.9e-5) × 5000 +                  # ≈ 5000 (local outbreak)
  7.9e-6 × 0.757 × 50 +                  # ≈ 0.0003 (Ethiopia)
  2.3e-5 × 0.496 × 100                   # = 0.001 (Somalia)
] / 178,000,000

= 5000.001 / 178,000,000
= 2.81 × 10⁻⁵  ← 100× higher than Ethiopia!
```

**For Somalia (receiving infections):**
```
ȳ_SOM = [
  (1 - 2.3e-5) × 100 +                   # ≈ 100 (local)
  7.9e-6 × 0.243 × 50 +                  # ≈ 0.00001 (Ethiopia)
  4.9e-5 × 0.241 × 5000                  # = 0.059 (Kenya export)
] / 178,000,000

= (100 + 0.059) / 178,000,000
= 5.62 × 10⁻⁷
```

---

### Step 4: Interpret the Coupling

**Key Insights:**

1. **Kenya's outbreak increases risk in neighbors:**
   - Kenya → Ethiopia transmission: `τ_KEN × π[KEN→ETH] × 5000 = 4.9e-5 × 0.759 × 5000 = 0.186 infected travelers/day`
   - Kenya → Somalia transmission: `τ_KEN × π[KEN→SOM] × 5000 = 4.9e-5 × 0.241 × 5000 = 0.059 infected travelers/day`

2. **Ethiopia is at higher risk than Somalia because:**
   - π[KEN→ETH] = 0.759 > π[KEN→SOM] = 0.241 (gravity model favors Ethiopia)
   - Ethiopia is larger (more attractive) and closer to Kenya's population centers

3. **τ values modulate coupling strength:**
   - Kenya's high τ_KEN = 4.9e-5 means it exports infections more readily
   - Ethiopia's low τ_ETH = 7.9e-6 means it barely exports (even if it had cases)
   - Somalia's intermediate τ_SOM = 2.3e-5 puts it in between

4. **Distance and population matter:**
   - Even though Somalia is slightly closer to Kenya (680 km vs 760 km),
   - Ethiopia receives more Kenyan travelers due to its much larger population
   - The gravity model balances both factors via ω and γ

---

### Step 5: Spatial Hazard (Importation Risk)

Finally, the spatial hazard ℋ_{jt} converts this gravity-weighted prevalence into a **daily probability of at least one imported infection**.

For Ethiopia receiving infections from the Kenyan outbreak:

```r
S*_ETH = (1 - 7.9e-6) × 110,000,000 ≈ 110,000,000
β_ETH = 0.5  # transmission rate (example)

ℋ_ETH = [β × S* × (1 - exp{-(S*/N) × ȳ})] / [1 + β × S*]
      = [0.5 × 110M × (1 - exp{-(110M/112M) × 2.82e-7})] / [1 + 0.5 × 110M]
      ≈ [0.5 × 110M × 3.1e-2] / [1 + 55M]
      ≈ 1.7M / 55M
      ≈ 0.031 = 3.1% daily probability of importation from Kenya
```

**This means:**
- Without the Kenyan outbreak: Ethiopia's hazard is driven by local cases (50)
- With the Kenyan outbreak: Ethiopia has ~3% chance/day of importing infection
- Over 30 days: cumulative risk ≈ 1 - (1 - 0.031)³⁰ ≈ 61% of importation event

---

## Summary: How Parameters Control Coupling

| Parameter | Effect on Cross-Border Transmission |
|-----------|-------------------------------------|
| **τᵢ (origin)** | Higher → more infected travelers leave country *i* |
| **τⱼ (destination)** | Higher → downweight local cases, upweight imports |
| **mobility_gamma (γ)** | Higher → distance decay stronger → prefer nearby countries |
| **mobility_omega (ω)** | Higher → large populations more attractive |
| **Distance d_{ij}** | Larger → lower π_{ij} → fewer travelers between *i* and *j* |
| **Population N_j** | Larger → higher π_{ij} → more travelers attracted to *j* |

---

## What Happens in Independent Country Models?

When you run countries independently (as in [vm/run_single_country.R](vm/run_single_country.R)):

```r
# These are set to FALSE:
control$sampling$sample_tau_i <- FALSE
control$sampling$sample_mobility_gamma <- FALSE
control$sampling$sample_mobility_omega <- FALSE
```

**Effect:**
- No gravity-weighted prevalence from other countries
- ȳ_{jt} contains only local infections: `(1 - τ_j) × infected_j`
- Each country is its own isolated system
- Faster (no need to track cross-border flows)
- Appropriate when countries are far apart or borders are closed

---

## References

**Mathematical Foundation:**
- Bjørnstad, O. N., & Grenfell, B. T. (2008). "Hazards, spatial transmission and timing of outbreaks in epidemic metapopulations." *Journal of Theoretical Ecology*, 1, 145-153.

**Parameter Estimation:**
- Kraemer et al. (2020). "Utilizing general human movement models to predict the spread of emerging infectious diseases in resource poor settings." *Scientific Reports*.
- Mobility data: 2017 OAG (Official Airline Guide) flight schedules for Sub-Saharan Africa

**Code Implementation:**
- [R/calc_diffusion_matrix_pi.R](R/calc_diffusion_matrix_pi.R) - Gravity model
- [R/calc_spatial_hazard.R](R/calc_spatial_hazard.R) - Cross-border transmission
- [R/est_mobility.R](R/est_mobility.R) - Parameter estimation from flight data
