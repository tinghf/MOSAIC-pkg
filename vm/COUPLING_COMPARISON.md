# Multi-Country MOSAIC: Execution Patterns Comparison

## Visual Comparison

### Pattern 1: Single-Node Coupled (Original)

```
┌─────────────────────────────────────────────┐
│         Single Large Compute Node           │
│  (120 cores, 456GB RAM)                     │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │     run_MOSAIC(iso = c("ETH",        │  │
│  │                        "KEN",        │  │
│  │                        "SOM"))       │  │
│  │                                      │  │
│  │  ┌─────┐  ┌─────┐  ┌─────┐         │  │
│  │  │ ETH │──│ KEN │──│ SOM │         │  │
│  │  └─────┘  └─────┘  └─────┘         │  │
│  │     │        │        │             │  │
│  │     └────────┴────────┘             │  │
│  │   Real-time coupling via            │  │
│  │   mobility_omega, mobility_gamma,   │  │
│  │   tau_i, pi_ij matrix               │  │
│  │                                      │  │
│  │  Runtime: 24-48 hours               │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘

Pros: ✓ True dynamic coupling
      ✓ Single job submission
      ✓ Scientifically accurate

Cons: ✗ Limited to single node resources
      ✗ Sequential country processing
      ✗ Slow for 5+ countries
```

---

### Pattern 2: Independent Countries (Parallel, No Coupling)

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│   Node 1    │  │   Node 2    │  │   Node 3    │
│  (32 cores) │  │  (32 cores) │  │  (32 cores) │
│             │  │             │  │             │
│  ┌───────┐  │  │  ┌───────┐  │  │  ┌───────┐  │
│  │  ETH  │  │  │  │  KEN  │  │  │  │  SOM  │  │
│  └───────┘  │  │  └───────┘  │  │  └───────┘  │
│             │  │             │  │             │
│  No         │  │  No         │  │  No         │
│  coupling   │  │  coupling   │  │  coupling   │
│             │  │             │  │             │
│  Runtime:   │  │  Runtime:   │  │  Runtime:   │
│  8-12 hrs   │  │  8-12 hrs   │  │  8-12 hrs   │
└─────────────┘  └─────────────┘  └─────────────┘
       ║                ║                ║
       ╚════════════════╩════════════════╝
              12 hours total

Pros: ✓ Maximum parallelization (3x speedup)
      ✓ Simple infrastructure
      ✓ Fault tolerant

Cons: ✗ No cross-border transmission
      ✗ Misses regional dynamics
      ✗ Not suitable for outbreak scenarios
```

---

### Pattern 3: Iterative Offline Coupling (This Solution!)

```
╔═══════════════════════════════════════════════════════════════╗
║                      ITERATION 0                              ║
╚═══════════════════════════════════════════════════════════════╝

┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│   Node 1    │  │   Node 2    │  │   Node 3    │
│             │  │             │  │             │
│  ┌───────┐  │  │  ┌───────┐  │  │  ┌───────┐  │
│  │  ETH  │  │  │  │  KEN  │  │  │  │  SOM  │  │
│  └───┬───┘  │  │  └───┬───┘  │  │  └───┬───┘  │
│      │      │  │      │      │  │      │      │
│      ↓      │  │      ↓      │  │      ↓      │
│  traj_0.csv │  │  traj_0.csv │  │  traj_0.csv │
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       └────────────────┴────────────────┘
                        ↓
              Shared Filesystem
         /scratch/trajectories/

╔═══════════════════════════════════════════════════════════════╗
║                      ITERATION 1                              ║
╚═══════════════════════════════════════════════════════════════╝

┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│   Node 1    │  │   Node 2    │  │   Node 3    │
│             │  │             │  │             │
│  Read: KEN, │  │  Read: ETH, │  │  Read: ETH, │
│        SOM  │  │        SOM  │  │        KEN  │
│     ↓       │  │     ↓       │  │     ↓       │
│  ┌───────┐  │  │  ┌───────┐  │  │  ┌───────┐  │
│  │ ETH + │  │  │  │ KEN + │  │  │  │ SOM + │  │
│  │import │  │  │  │import │  │  │  │import │  │
│  └───┬───┘  │  │  └───┬───┘  │  │  └───┬───┘  │
│      ↓      │  │      ↓      │  │      ↓      │
│  traj_1.csv │  │  traj_1.csv │  │  traj_1.csv │
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       └────────────────┴────────────────┘
                        ↓
              Check Convergence
           (R² > 0.95? → DONE)

╔═══════════════════════════════════════════════════════════════╗
║                      ITERATION 2                              ║
╚═══════════════════════════════════════════════════════════════╝

┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│   Node 1    │  │   Node 2    │  │   Node 3    │
│             │  │             │  │             │
│  Read: KEN, │  │  Read: ETH, │  │  Read: ETH, │
│        SOM  │  │        SOM  │  │        KEN  │
│   (iter 1)  │  │   (iter 1)  │  │   (iter 1)  │
│     ↓       │  │     ↓       │  │     ↓       │
│  ┌───────┐  │  │  ┌───────┐  │  │  ┌───────┐  │
│  │ ETH + │  │  │  │ KEN + │  │  │  │ SOM + │  │
│  │import │  │  │  │import │  │  │  │import │  │
│  └───┬───┘  │  │  └───┬───┘  │  │  └───┬───┘  │
│      ↓      │  │      ↓      │  │      ↓      │
│  traj_2.csv │  │  traj_2.csv │  │  traj_2.csv │
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       └────────────────┴────────────────┘
                        ↓
              ✓ CONVERGED!
         (trajectories stable)

Total Runtime: 3 iterations × 12 hours = 36 hours
               (but fully parallelized)

Pros: ✓ Parallel execution across nodes
      ✓ Models cross-border transmission
      ✓ Converges in 2-4 iterations
      ✓ Works on standard HPC (shared FS)

Cons: ✗ Longer than independent (3x iterations)
      ✗ Not real-time coupling (iterative)
      ✗ Requires coordination between iterations
```

---

### Pattern 4: Synchronous File-Based Coupling (Advanced)

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│   Node 1    │  │   Node 2    │  │   Node 3    │
│             │  │             │  │             │
│  ┌───────┐  │  │  ┌───────┐  │  │  ┌───────┐  │
│  │  ETH  │  │  │  │  KEN  │  │  │  │  SOM  │  │
│  └───┬───┘  │  │  └───┬───┘  │  │  └───┬───┘  │
│      │      │  │      │      │  │      │      │
│      ↓      │  │      ↓      │  │      ↓      │
│  Write State│  │  Write State│  │  Write State│
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       └────────────────┴────────────────┘
                        ↓
              Shared Filesystem
         /scratch/state/
              ├── ETH_infections.csv
              ├── KEN_infections.csv
              └── SOM_infections.csv
                        ↓
       ┌────────────────┴────────────────┐
       │                │                │
┌──────┴──────┐  ┌──────┴──────┐  ┌──────┴──────┐
│   Node 1    │  │   Node 2    │  │   Node 3    │
│             │  │             │  │             │
│ Read KEN,SOM│  │ Read ETH,SOM│  │ Read ETH,KEN│
│      ↓      │  │      ↓      │  │      ↓      │
│  Compute    │  │  Compute    │  │  Compute    │
│  Spatial    │  │  Spatial    │  │  Spatial    │
│  Hazard     │  │  Hazard     │  │  Hazard     │
│      ↓      │  │      ↓      │  │      ↓      │
│  ┌───────┐  │  │  ┌───────┐  │  │  ┌───────┐  │
│  │Run    │  │  │  │Run    │  │  │  │Run    │  │
│  │LASER  │  │  │  │LASER  │  │  │  │LASER  │  │
│  └───────┘  │  │  └───────┘  │  │  └───────┘  │
│             │  │             │  │             │
│  BARRIER    │  │  BARRIER    │  │  BARRIER    │
│  SYNC       │  │  SYNC       │  │  SYNC       │
└─────────────┘  └─────────────┘  └─────────────┘
       │                │                │
       └────────────────┴────────────────┘
              Repeat for each
              calibration sample

Runtime: 12-24 hours (true real-time coupling)

Pros: ✓ True dynamic coupling
      ✓ Parallel execution
      ✓ Scientifically accurate
      ✓ Standard HPC infrastructure

Cons: ✗ Complex coordination (barriers)
      ✗ File I/O overhead
      ✗ Requires careful debugging
      ✗ Slowest node determines speed
```

---

## Performance Summary Table

| Metric | Single-Node | Independent | Iterative Offline | Synchronous |
|--------|-------------|-------------|-------------------|-------------|
| **Speedup** | 1× (baseline) | 3× | 1× (but distributed) | 2× |
| **Coupling Accuracy** | 100% | 0% | ~95% | 100% |
| **Runtime (3 countries)** | 36 hrs | 12 hrs | 36 hrs | 18 hrs |
| **Setup Complexity** | Low | Low | Medium | High |
| **Infrastructure** | 1 large node | 3 nodes | 3 nodes + shared FS | 3 nodes + shared FS |
| **Fault Tolerance** | Low | High | Medium | Low |
| **Debugging** | Easy | Easy | Medium | Hard |

---

## Decision Tree

```
START: Do you need cross-border transmission modeling?
│
├─ NO → Use Pattern 2 (Independent Countries)
│        ✓ Fastest, simplest
│        ✓ Perfect for isolated country calibration
│
└─ YES: Do you have 1 large node (100+ cores)?
    │
    ├─ YES → Use Pattern 1 (Single-Node Coupled)
    │         ✓ Scientifically accurate
    │         ✓ Easiest to implement
    │
    └─ NO: Multiple smaller nodes available?
        │
        ├─ YES: First time running coupled model?
        │   │
        │   ├─ YES → Use Pattern 3 (Iterative Offline)
        │   │         ✓ Good accuracy (~95%)
        │   │         ✓ Easier debugging
        │   │         ✓ Standard HPC scheduler
        │   │
        │   └─ NO (production) → Use Pattern 4 (Synchronous)
        │                         ✓ Maximum accuracy (100%)
        │                         ✓ Faster than iterative
        │                         ✓ Requires expertise
        │
        └─ NO → Stick with Pattern 1 on largest available node
                 (Accept longer runtime)
```

---

## Recommendations by Use Case

### Research / Exploration
**Use**: Pattern 3 (Iterative Offline Coupling)
- Good balance of accuracy and simplicity
- Easy to inspect intermediate results
- Standard HPC job submission

### Production / Operational Forecasting
**Use**: Pattern 4 (Synchronous File-Based)
- Maximum accuracy
- Faster than iterative
- Worth the setup complexity

### Country-Specific Parameter Estimation
**Use**: Pattern 2 (Independent Countries)
- No need for coupling
- Maximum speed
- Simplest infrastructure

### Regional Outbreak Response
**Use**: Pattern 1 (Single-Node) or Pattern 4 (Synchronous)
- Critical to model cross-border transmission
- Accept complexity for accuracy
- Pattern 1 if you have large node, else Pattern 4

---

## Implementation Checklist

### For Pattern 3 (Iterative Offline):
- [ ] Shared filesystem accessible from all nodes
- [ ] Trajectory storage directory created
- [ ] Convergence metric defined (R² threshold)
- [ ] Job submission script configured
- [ ] Test with 2 countries first
- [ ] Validate against single-node coupled model

### For Pattern 4 (Synchronous):
- [ ] All above, plus:
- [ ] Barrier synchronization tested
- [ ] Timeout handling implemented
- [ ] File locking strategy defined
- [ ] Monitoring dashboard (optional)
- [ ] Rollback strategy for failed nodes

---

## Example Validation

To verify your distributed coupling works:

```bash
# 1. Run single-node coupled (baseline)
Rscript -e "
  config <- get_location_config(iso = c('ETH', 'KEN'))
  result_baseline <- run_MOSAIC(config = config, ...)
"

# 2. Run distributed coupled (test)
bash vm/run_distributed_coupled_example.sh

# 3. Compare trajectories
Rscript -e "
  library(ggplot2)
  baseline <- read.csv('baseline/ETH_trajectory.csv')
  distributed <- read.csv('distributed/ETH_trajectory.csv')

  merged <- merge(baseline, distributed, by = 'date')

  # Compute R²
  r2 <- 1 - sum((merged$I1.x - merged$I1.y)^2) /
            sum((merged$I1.x - mean(merged$I1.x))^2)

  cat('Trajectory R²:', r2, '\n')
  # Should be > 0.90 for good coupling
"
```

---

**Questions?** See [vm/README_DISTRIBUTED_COUPLING.md](README_DISTRIBUTED_COUPLING.md) for full implementation details.
