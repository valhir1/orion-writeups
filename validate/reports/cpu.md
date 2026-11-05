# cpu
Sources: lscpu.log, dmidecode-processor.log, cpu-stress.log, hwmon.log

- **INFO** Model name: AMD Ryzen Threadripper 9960X 24-Cores (`logs/lscpu.log:10`)
- **INFO** CPU(s): 48 (`logs/lscpu.log:7`)
- **INFO** Core(s) per socket: 24 (`logs/lscpu.log:14`)
- **PASS** Processor Status: Populated, Enabled (`logs/dmidecode-processor.log:46`)
- **PASS** Thread Count matches CPU(s): 48 (`logs/dmidecode-processor.log:56`)
- **INFO** PY_STRESS_ITERATIONS_TOTAL: 47806062964 (`logs/cpu-stress.log:4`)
- **PASS** Stress test ok (`logs/cpu-stress.log:6`)
- **INFO** TEMP_BEFORE_C: 70 (`logs/cpu-stress.log:3`)
- **INFO** TEMP_MAX_DURING_C: 95 (`logs/cpu-stress.log:7`)
- **INFO** TEMP_AFTER_C: 95 (`logs/cpu-stress.log:8`)
- **PASS** max temp within limit (`logs/cpu-stress.log:7`)
- **INFO** k10temp Tctl: 71.0 C (`logs/hwmon.log:20`)
