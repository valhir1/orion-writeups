#!/usr/bin/env python3
import re, os, datetime
B="${VALIDATE_DIR}"; L_=B+"/logs"; R=B+"/reports"; os.makedirs(R,exist_ok=True)
def rd(f):
 p=L_+"/"+f
 return open(p).readlines() if os.path.exists(p) else None
def kv(lines,key,a=1,b=None):
 if not lines: return (None,None)
 b=len(lines)+1 if b is None else b
 for i in range(a-1,min(b,len(lines))):
  m=re.match(r'^\s*'+re.escape(key)+r'\s*:\s*(.*)$',lines[i])
  if m: return (i+1,m.group(1).strip())
 return (None,None)
def L(out,v,t,f,ln): out.append(f"- **{v}** {t} (`logs/{f}:{ln}`)")
def mask(v):
 v=v.replace("*","").strip(); return "****"+v[-4:] if len(v)>=4 else "****"+v
def skip(out,f): L(out,"SKIPPED",f+" missing",f,0)
def chk(lines,f,out):
 if not lines: skip(out,f); return True
 for i,l in enumerate(lines):
  if "NEEDS_SUDO" in l: L(out,"SKIPPED",l.strip(),f,i+1)
  elif "NOT_INSTALLED" in l: L(out,"SKIPPED",l.strip(),f,i+1)
 has_content=any(l.strip() and not l.startswith("#") and "NEEDS_SUDO" not in l and "NOT_INSTALLED" not in l and not l.startswith("sudo:") for l in lines)
 return not has_content
def page(part,srcs,body):
 lines=[f"# {part}","Sources: "+", ".join(srcs),""]+body
 open(R+"/"+part+".md","w").write("\n".join(lines)+"\n")
 c={v:sum(1 for x in body if x.startswith(f"- **{v}**")) for v in["PASS","FAIL","INFO","SKIPPED"]}
 ov="FAIL" if c["FAIL"] else("PASS" if c["PASS"] else"INFO")
 return(part,c,ov)
pages=[]
cp=None
lc=rd("lscpu.log"); dp=rd("dmidecode-processor.log"); st=rd("cpu-stress.log"); hw=rd("hwmon.log"); cb=[]
if not chk(lc,"lscpu.log",cb):
 for k in["Model name","CPU(s)","Core(s) per socket"]:
  ln,v=kv(lc,k)
  if ln: L(cb,"INFO",f"{k}: {v}","lscpu.log",ln)
 cp=kv(lc,"CPU(s)")[1]
if not chk(dp,"dmidecode-processor.log",cb):
 ln,v=kv(dp,"Status")
 if ln: L(cb,"PASS" if"Populated, Enabled"in v else"FAIL",f"Processor Status: {v}","dmidecode-processor.log",ln)
 ln,tc=kv(dp,"Thread Count")
 if ln and cp: L(cb,"PASS" if int(tc)==int(cp) else"FAIL",f"Thread Count matches CPU(s): {tc}","dmidecode-processor.log",ln)
if not chk(st,"cpu-stress.log",cb):
 ln,ex=kv(st,"PY_STRESS_EXIT"); ln2,wr=kv(st,"PY_STRESS_WORKERS"); ln3,it=kv(st,"PY_STRESS_ITERATIONS_TOTAL")
 if ln3: L(cb,"INFO",f"PY_STRESS_ITERATIONS_TOTAL: {it}","cpu-stress.log",ln3)
 ok=ex=="0" and((wr and cp and int(wr)==int(cp)) or"successful run completed"in"".join(st))
 L(cb,"PASS" if ok else"FAIL","Stress test ok" if ok else"Stress test fail","cpu-stress.log",ln or 0)
 for k in["TEMP_BEFORE_C","TEMP_MAX_DURING_C","TEMP_AFTER_C"]:
  ln,v=kv(st,k)
  if ln: L(cb,"INFO",f"{k}: {v}","cpu-stress.log",ln)
 ln,mx=kv(st,"TEMP_MAX_DURING_C")
 if ln: L(cb,"PASS" if int(mx)<=100 else"FAIL","max temp within limit" if int(mx)<=100 else"max temp exceeded","cpu-stress.log",ln)
if not chk(hw,"hwmon.log",cb):
 ln,v=kv(hw,"Tctl")
 if ln: L(cb,"INFO",f"k10temp Tctl: {int(v)/1000:.1f} C","hwmon.log",ln)
pages.append(page("cpu",["lscpu.log","dmidecode-processor.log","cpu-stress.log","hwmon.log"],cb))
bb=rd("dmidecode-baseboard.log"); dm=rd("dmidecode-memory.log"); fr=rd("free.log"); ed=rd("edac.log"); md=rd("mdstat.log"); up=rd("uptime.log"); mt=rd("memtester.log"); bm=[]
if not chk(bb,"dmidecode-baseboard.log",bm):
 for k in["Manufacturer","Product Name","Serial Number"]:
  ln,v=kv(bb,k)
  if ln: L(bm,"INFO",f"{k}: "+(mask(v) if k=="Serial Number" else v),"dmidecode-baseboard.log",ln)
if not chk(dm,"dmidecode-memory.log",bm):
 ln,v=kv(dm,"Error Correction Type")
 if ln: L(bm,"INFO",f"Error Correction Type: {v}","dmidecode-memory.log",ln)
 dtot=0; indev=False
 for i,l in enumerate(dm):
  if re.match(r'^Memory Device$',l.strip()): indev=True; continue
  if indev and re.match(r'^\s*Size:\s*(.+)$',l):
   s=l.split(":",1)[1].strip()
   if s!="No Module Installed":
    dtot+=int(re.search(r'(\d+)\s*GB',s).group(1))
    end=len(dm)+1
    for j in range(i+1,len(dm)):
     if re.match(r'^Handle 0x',dm[j].strip()): end=j+1; break
    b=kv(dm,"Bank Locator",i+1,end); p=kv(dm,"Part Number",i+1,end); sp=kv(dm,"Configured Memory Speed",i+1,end)
    L(bm,"INFO",f"{b[1] if b[0] else '?'}: {s}, {p[1] if p[0] else '?'}, configured {sp[1] if sp[0] else '?'}","dmidecode-memory.log",i+1)
  if indev and re.match(r'^Handle 0x',l.strip()): indev=False
if not chk(fr,"free.log",bm):
 ln,v=kv(fr,"Mem")
 if ln:
  ft=float(re.search(r'(\d+(?:\.\d+)?)\s*Gi',v).group(1))
  if dtot: L(bm,"PASS" if ft>=0.95*dtot else"FAIL",f"Memory: free {ft} GiB vs DIMM {dtot} GiB","free.log",ln)
  else: L(bm,"INFO",f"Free memory total: {ft} GiB","free.log",ln)
if not chk(ed,"edac.log",bm):
 ln,_=kv(ed,"NO_MATCHES")
 if ln: L(bm,"INFO","no edac/ecc/mce kernel messages","edac.log",ln)
 else:
  c=0
  for i,l in enumerate(ed):
   if not l.startswith("#") and not l.startswith("NO_MATCHES") and re.match(r'^\s*\S',l) and c<10:
    L(bm,"INFO",l.strip(),"edac.log",i+1); c+=1
 for i,l in enumerate(ed):
  m=re.match(r'^EDAC sysfs:.*ce_count=(\d+)\s+ue_count=(\d+)',l)
  if m: L(bm,"PASS" if m.group(1)=="0" and m.group(2)=="0" else"FAIL",f"EDAC ce={m.group(1)} ue={m.group(2)}","edac.log",i+1)
if not chk(md,"mdstat.log",bm):
 ln,v=kv(md,"Personalities")
 if ln: L(bm,"INFO",f"Personalities: {v}","mdstat.log",ln)
if not chk(up,"uptime.log",bm):
 for i,l in enumerate(up):
  if not l.startswith("#") and"up"in l: L(bm,"INFO",l.strip(),"uptime.log",i+1); break
if not chk(mt,"memtester.log",bm):
 t="".join(mt)
 L(bm,"PASS" if"Done."in t and"FAILURE"not in t else"FAIL","memtester ok" if"Done."in t and"FAILURE"not in t else"memtester fail","memtester.log",1)
pages.append(page("board-memory",["dmidecode-baseboard.log","dmidecode-memory.log","free.log","edac.log","mdstat.log","uptime.log","memtester.log"],bm))
# GPU
def gsec(lines,n):
 hs=[i+1 for i,l in enumerate(lines) if re.match(r'^GPU [0-9A-Fa-f:.]+$',l.strip())]
 if n>=len(hs): return None
 return(hs[n],hs[n+1] if n+1<len(hs) else len(lines)+1)
def gkv(lines,n,key):
 s=gsec(lines,n)
 if not s: return(None,None)
 return kv(lines,key,s[0],s[1])
for n in[0,1]:
 lp=rd(f"lspci-gpu{n}.log"); sq=rd("nvidia-smi-q.log"); sc=rd("nvidia-smi-csv.log"); gb=[]
 if not chk(lp,f"lspci-gpu{n}.log",gb):
  mc=re.search(r'^LNKCAP_SUMMARY:.*Speed (\S+), Width (x\d+)',"".join(lp),re.M)
  ms=re.search(r'^LNKSTA_SUMMARY:.*Speed (\S+), Width (x\d+)',"".join(lp),re.M)
  if mc and ms:
   ln=next(i+1 for i,l in enumerate(lp) if"LNKSTA_SUMMARY"in l)
   L(gb,"PASS" if mc.group(2)==ms.group(2) else"FAIL",f"PCIe Width: {ms.group(2)} vs cap {mc.group(2)}",f"lspci-gpu{n}.log",ln)
   if mc.group(1)==ms.group(1): L(gb,"PASS",f"PCIe Speed: {ms.group(1)}",f"lspci-gpu{n}.log",ln)
   else: L(gb,"INFO",f"link speed below cap (may be idle power saving): {ms.group(1)} vs {mc.group(1)}",f"lspci-gpu{n}.log",ln)
 if not chk(sq,"nvidia-smi-q.log",gb):
  for k in["Product Name","VBIOS Version","Bus Id","Serial Number","GPU UUID"]:
   ln,v=gkv(sq,n,k)
   if ln: L(gb,"INFO",f"{k}: "+(mask(v) if k in["Serial Number","GPU UUID"] else v),"nvidia-smi-q.log",ln)
  for k in["DRAM Uncorrectable","SRAM Uncorrectable SEC-DED","Remapped Rows","Double Bit ECC"]:
   ln,v=gkv(sq,n,k)
   if ln:
    if v=="N/A": L(gb,"INFO",f"{k}: N/A (consumer card, not reported)","nvidia-smi-q.log",ln)
    elif v.isdigit() and int(v)>0: L(gb,"FAIL",f"{k}: {v}","nvidia-smi-q.log",ln)
    else: L(gb,"PASS",f"{k}: {v}","nvidia-smi-q.log",ln)
  for k in["Channel Repair Pending","TPC Repair Pending"]:
   ln,v=gkv(sq,n,k)
   if ln: L(gb,"PASS" if v=="No" else"FAIL",f"{k}: {v}","nvidia-smi-q.log",ln)
  for k in["HW Slowdown","HW Thermal Slowdown","HW Power Brake Slowdown","SW Thermal Slowdown"]:
   ln,v=gkv(sq,n,k)
   if ln: L(gb,"PASS" if v=="Not Active" else"FAIL",f"{k}: {v}","nvidia-smi-q.log",ln)
  ln,v=gkv(sq,n,"GPU Current Temp")
  if ln: L(gb,"INFO",f"GPU Current Temp: {v}","nvidia-smi-q.log",ln)
 if not chk(sc,"nvidia-smi-csv.log",gb):
  hdr=[h.strip() for h in sc[2].split(",")]
  row=None; rln=0
  for i in range(3,len(sc)):
   if sc[i].strip().split(",")[0].strip()==str(n):
    row=[c.strip() for c in sc[i].split(",")]; rln=i+1; break
  if row:
   d=dict(zip(hdr,row))
   wc=d.get("pcie.link.width.current",""); wm=d.get("pcie.link.width.max","")
   L(gb,"PASS" if wc==wm else"FAIL",f"PCIe width current {wc} vs max {wm}","nvidia-smi-csv.log",rln)
   gc=d.get("pcie.link.gen.current",""); gm=d.get("pcie.link.gen.max","")
   if gc==gm: L(gb,"PASS",f"PCIe gen {gc}","nvidia-smi-csv.log",rln)
   else: L(gb,"INFO",f"link speed below cap (may be idle power saving): gen {gc} vs {gm}","nvidia-smi-csv.log",rln)
   for k in["clocks.sm","clocks.mem","power.draw","memory.used","memory.total"]:
    if k in d: L(gb,"INFO",f"{k}: {d[k]}","nvidia-smi-csv.log",rln)
   t=d.get("temperature.gpu","")
   if t: L(gb,"PASS" if int(t)<=90 else"FAIL",f"temperature.gpu: {t} C","nvidia-smi-csv.log",rln)
 gb.append("- Load evidence (not copied): [bench results](${BENCH_DIR}/results)")
 pages.append(page(f"gpu{n}",[f"lspci-gpu{n}.log","nvidia-smi-q.log","nvidia-smi-csv.log"],gb))
# NVMe
for n in[0,1,2]:
 sv=rd(f"smart-nvme{n}n1.log"); nb=[]
 if not chk(sv,f"smart-nvme{n}n1.log",nb):
  for k in["Model Number","Firmware Version","Serial Number"]:
   ln,v=kv(sv,k)
   if ln: L(nb,"INFO",f"{k}: "+(mask(v) if k=="Serial Number" else v),f"smart-nvme{n}n1.log",ln)
  ln,v=kv(sv,"size_sectors")
  if ln: L(nb,"INFO",f"size_sectors: {v}",f"smart-nvme{n}n1.log",ln)
  ln,v=kv(sv,"SMART overall-health self-assessment test result")
  if ln: L(nb,"PASS" if"PASSED"in v else"FAIL",f"SMART overall-health: {v}",f"smart-nvme{n}n1.log",ln)
  ln,v=kv(sv,"Critical Warning")
  if ln: L(nb,"PASS" if v=="0x00" else"FAIL",f"Critical Warning: {v}",f"smart-nvme{n}n1.log",ln)
  ln,v=kv(sv,"Media and Data Integrity Errors")
  if ln: L(nb,"PASS" if v.replace(",","")=="0" else"FAIL",f"Media and Data Integrity Errors: {v}",f"smart-nvme{n}n1.log",ln)
  ln,asp=kv(sv,"Available Spare"); ln2,thr=kv(sv,"Available Spare Threshold")
  if ln and ln2:
   a=int(asp.replace("%","")); t2=int(thr.replace("%",""))
   L(nb,"PASS" if a>=t2 else"FAIL",f"Available Spare {asp} >= Threshold {thr}",f"smart-nvme{n}n1.log",ln)
  ln,v=kv(sv,"Percentage Used")
  if ln: L(nb,"PASS" if int(v.replace("%",""))<90 else"FAIL",f"Percentage Used: {v}",f"smart-nvme{n}n1.log",ln)
  for k in["Power On Hours","Data Units Written","Unsafe Shutdowns","Temperature","Error Information Log Entries"]:
   ln,v=kv(sv,k)
   if ln: L(nb,"INFO",f"{k}: {v}",f"smart-nvme{n}n1.log",ln)
 pages.append(page(f"nvme{n}",[f"smart-nvme{n}n1.log"],nb))
# INDEX
idx=["# Hardware validation INDEX",f"Generated: {datetime.datetime.now().isoformat()}","",
"| Part | Page | PASS | FAIL | INFO | SKIPPED | Overall |","|---|---|---|---|---|---|---|"]
for p,c,ov in pages:
 idx.append(f"| {p} | {p}.md | {c['PASS']} | {c['FAIL']} | {c['INFO']} | {c['SKIPPED']} | {ov} |")
idx.append("")
idx.append("Raw logs: ../logs/")
open(R+"/INDEX.md","w").write("\n".join(idx)+"\n")
