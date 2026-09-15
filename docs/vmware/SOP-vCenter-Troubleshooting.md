# SOP — VMware vCenter Server Troubleshooting
## Standard Operating Procedures for the 5 Most Common vCenter Platform (Feature) Issues and the 5 Most Common Virtual Machine Issues on vCenter

---

## Document Control

| Field | Value |
|---|---|
| Document ID | SOP-VMW-VC-001 |
| Title | VMware vCenter Server Troubleshooting SOP (Platform + Virtual Machine Issues) |
| Version | 1.0 |
| Status | Approved / Effective |
| Owner | Virtualization & Cloud Platform Team |
| Author | Platform Engineering |
| Approver | IT Infrastructure Manager / Change Advisory Board |
| Effective date | 2026-09-15 |
| Next review date | 2026-09-15 + 12 months (or on major vSphere release / major incident) |
| Review cycle | Annual, plus after any Severity-1/2 incident involving vCenter |
| Classification | Internal — Operational Runbook (may contain infrastructure details; do not publish externally) |
| Applies to | VMware vSphere 6.7 U3, 7.0 U3, 8.0 U1–U3 and later (VMware Cloud Foundation / vSphere Foundation equivalent builds) |
| Change record | Create a change record for every procedure in Part A/B before execution, except for explicitly marked *Emergency (break-fix)* steps |

### Revision History

| Version | Date | Author | Change |
|---|---|---|---|
| 0.1 | 2026-09-15 | Platform Engineering | Initial draft: scope, governance, triage matrix, tooling |
| 1.0 | 2026-09-15 | Platform Engineering | Issued: 5 vCenter platform SOPs (A1–A5), 5 VM SOPs (B1–B5), appendices, monitoring and escalation model |

---

## 1. Purpose

This SOP provides a repeatable, auditable, evidence-based method for diagnosing and resolving the ten most frequently encountered VMware vCenter–related incidents:

* **Part A — vCenter platform / feature issues:** certificate expiry, services failing to start, appliance storage (`/storage/*`) exhaustion, vCenter High Availability (VCHA) failover, and file-based backup/restore.
* **Part B — virtual machine issues as seen and managed from vCenter:** VM file locks preventing power-on, snapshot consolidation, vMotion/migration failures, vSphere HA admission-control power-on blocks, and VM performance degradation.

The objectives are to:

1. Reduce Mean Time To Detect (MTTD) and Mean Time To Resolve (MTTR) through a fixed triage path.
2. Prevent *secondary* outages caused by unguarded remediation (snapshot misuse, forced lock removal, manual database file deletion, deleting delta disks).
3. Produce consistent evidence (logs, commands, timestamps) suitable for Problem Management and Broadcom (VMware) support cases.
4. Drive prevention through monitoring thresholds, capacity governance and a maintenance calendar (Appendix E).

### 1.1 Success criteria

| Criterion | Target |
|---|---|
| Triage classification (which SOP applies) | ≤ 15 minutes from alert/incident start |
| Evidence pack captured before any change | 100% of Severity 1–2 incidents |
| vCenter fully functional after Part A procedure | All services `Running`, UI and VAMI reachable, hosts `Connected` |
| VM fully functional after Part B procedure | VM powers on / migrates / consolidates, no outstanding warnings, backup re-verified |
| Repeated incident within 30 days for same root cause | 0 |

---

## 2. Scope

### 2.1 In scope

* vCenter Server Appliance (VCSA) 6.7 U3 / 7.0 / 8.0 and later, **appliance form factor**. Windows-based vCenter Server (6.7 and earlier) is referenced only via legacy KBs; it is end-of-life and remediation should be a migration project.
* In-guest-independent VM lifecycle operations managed through vCenter: power operations, snapshots, consolidation, migration (vMotion/SvMotion), vSphere HA/DRS interactions, VM hardware configuration.
* Platform services: vpxd, the services framework (vmon), vSphere Client / VAMI interfaces, STS/SSO certificate stores, the vCenter database (VCDB) partitioning, VCHA, file-based backup.

### 2.2 Out of scope

| Topic | Where it belongs |
|---|---|
| vCenter **deployment/upgrade** failures (installer, upgrade harness, pre-checks) | Separate build/upgrade runbook |
| ESXi host hardware failure, PSOD root-cause, firmware/driver remediation | Vendor hardware SOP + Broadcom support |
| vSAN health service failures and vSAN disk group rebuilds | vSAN Operations SOP |
| NSX / VDS (distributed switch) control-plane incidents | Network virtualization SOP |
| Guest OS / application defects, in-guest tuning beyond VM-level right-sizing | Application team SOP |
| Backup application defects (Veeam / Commvault / Dell etc.) | Backup platform SOP (this SOP covers only the *vSphere-side* symptoms: hot-added disks, locks, consolidation) |

### 2.3 Assumptions

* A configuration baseline exists (NTP, DNS forward/reverse, certificate inventory, HA/DRS design, snapshot policy).
* Root (VCSA) and administrator@vsphere.local credentials are held in the privileged access vault and are retrievable 24×7.
* Out-of-band access to the vCenter VM console (vSphere host client / DCUI / KVM) is available when the appliance UI is down.
* A change-management process exists with emergency-change provisions.

---

## 3. Audience, Roles and Responsibilities

**Audience:** L1 NOC / Service Desk, L2 Virtualization Administrators, L3 SME/Platform Architects, Change Manager, Backup Administrators, Application Owners.

| Activity | L1 NOC | L2 Virtualization Admin | L3 SME / Architect | Backup Admin | Change Manager | App Owner |
|---|---|---|---|---|---|---|
| Detect, raise incident, capture first evidence | **R** | C | I | — | I | — |
| Triage to SOP ID (A1–A5 / B1–B5) | C | **R** | C | C | I | I |
| Approve snapshot/change for remediation | I | C | C | I | **A** | I |
| Execute Part A procedures | — | **R** | C | — | I | I |
| Execute Part B procedures | — | **R** | C | C | I | I |
| VCHA failover / forced-standalone decisions | — | C | **R/A** | — | C | I |
| Backup integrity & test restore | — | C | C | **R** | I | I |
| Post-incident review, RCA, prevention actions | I | **R** | C | C | C | C |

*R = Responsible, A = Accountable/Approver, C = Consulted, I = Informed.*

### 3.1 Escalation matrix

| Tier | Trigger | Target response |
|---|---|---|
| L1 → L2 | vCenter UI/VAMI unreachable, or any Part A symptom | 15 min |
| L2 → L3 | L2 procedure fails **or** any STOP condition in this SOP is met or any datastore metadata operation is required | 30 min |
| L3 → Broadcom Support | Certificates cannot be renewed, VMDIR/`lsdoctor` involvement, VOMA required, VCHA isolated cluster, DB corruption, snapshot chain corruption | 30 min (Severity 1 case, SR raised immediately) |
| Notify Management/CAB | Any vCenter-down (S1) event, any use of an *Emergency* step, any admission-control disable | Immediately |

---

## 4. Severity Model

| Sev | Definition (violations) | Examples from this SOP | Response / Comms |
|---|---|---|---|
| **S1 Critical** | vCenter unavailable; management of all clusters lost; no workaround | A1 (certs expired → 503), A2, A3 (vpxd stopped), A4 (isolated VCHA, no failover) | Immediate; bridge call; 30-min updates; CAB notified |
| **S2 High** | Major capability degraded; multiple workloads impacted; workaround exists but is partial | B1 (cannot power on business-critical VM), B4 (power-on blocked cluster-wide), A5 (no recoverable backup) | Immediate; 1-hour updates |
| **S3 Medium** | Single workload or non-critical feature degraded | B2 (consolidation needed, backups failing), B3 (vMotion blocked for one VM), B5 (performance degradation) | Next business hours / maintenance window |
| **S4 Low** | Cosmetic, single warning, no functional impact | Certificate ≤ 60 days from expiry, snapshot > 72 h old | Planned change |

---

## 5. Prerequisites

### 5.1 Access and credentials

| Requirement | Detail | Checked by |
|---|---|---|
| VCSA SSH/console root access | Privileged vault; validated **before** an incident (test monthly) | L2 |
| SSO administrator | `administrator@vsphere.local` (or AD-equivalent group) with full admin rights | L2 |
| vSphere Client role | `Global Administrator` equivalent for certificate/HA operations | L2 |
| Out-of-band console | ESXi host client or DCUI reachable independently of vCenter | L2 |
| Backup/restore target access | SFTP/SCP/NFS/SMB credentials to the file-based backup destination | Backup Admin |
| Broadcom Support entitlement | Site ID, SR capability, ability to upload bundles | L3 |

### 5.2 Tools

| Tool | Where it runs | Purpose |
|---|---|---|
| `service-control`, `vmon-cli`, `vecs-cli`, `vmafd-cli` | VCSA (SSH, root) | Service and certificate store management |
| `certificate-manager` (VMCA utility) | VCSA `/usr/lib/vmware-vmca/bin/` | Certificate replacement/renewal (built-in) |
| **vCert** scripted tool | VCSA `/root` or `/tmp` | Broadcom-recommended certificate replacement/renewal on 7.x/8.x (KB 385107) |
| `psql` (vPostgres client) | VCSA `/opt/vmware/vpostgres/current/bin/` | VCDB inspection, purge scripts, evidence collection |
| `df`, `du`, `find`, `lsof` | VCSA / ESXi | Storage and lock investigation |
| `voma` | ESXi | VMFS on-disk metadata check (L3 + Broadcom only — see STOP conditions) |
| `vmfsfilelockinfo`, `vmkfstools -D`, `lsof` | ESXi | File-lock ownership |
| `esxcli`, `esxtop`, `vim-cmd`, `vmkfstools` | ESXi | VM/process/lock/performance inspection |
| VMware PowerCLI (`Connect-VIServer`, `Get-VM`, `Get-Stat`, `Get-Snapshot`, `Get-Cluster`) | Admin workstation | Inventory-wide checks, dashboards, remediation at scale |
| vSphere Client (HTML5) performance charts | Any browser | Baseline/compare charts without extra tooling |

### 5.3 Environment pre-checks (run before using this SOP as a recovery method)

```bash
# On the VCSA (root)
date; timedatectl status            # time must be NTP-synced; skew breaks certificates and VMDIR
service-control --status --all      # baseline service state
df -h; df -i                        # all appliance partitions
command -v cert-manager >/dev/null; ls /usr/lib/vmware-vmca/bin/certificate-manager
getent hosts "$(hostname -f)"       # FQDN must resolve forward and reverse to the appliance IP
```

```powershell
# From the admin workstation
Connect-VIServer vcsa.example.com -User administrator@vsphere.local
$global:DefaultVIServer | Select Name,Version,Build
Get-Cluster | Select Name,HAEnabled,DrrsEnabled    # note: property names vary by PowerCLI release
```

### 5.4 Snapshot discipline (mandatory before any Part A change)

| Rule | Requirement | Rationale |
|---|---|---|
| S-1 | Take the snapshot **only** as a short-term rollback point for a planned change | VM snapshots are **not** a backup method (Broadcom KB: best practices for VM snapshots) |
| S-2 | Delete/revert the snapshot within 24 h (72 h absolute maximum) | Delta growth, stun time, and consolidation risk |
| S-3 | In **Enhanced Linked Mode**, take **offline (powered-off)** snapshots of **all** vCenter nodes | Prevents VMDIR replication and stale-data divergence after partial revert |
| S-4 | If VCHA is configured, snapshot **only the Active node**; never the Passive/Witness | Snapshotting replica nodes breaks VCHA replication |
| S-5 | Never snapshot the VCSA while a file-based backup job is running | Concurrent snapshot + full backup is blocked/unsafe |
| S-6 | Record snapshot name, time, and owning change record | Traceability and forced cleanup |

---

## 6. Golden Rules (non-negotiable)

1. **Evidence first.** Capture logs, command output, and exact error text *before* changing anything. The text of the error is the single most valuable artifact.
2. **No unapproved remediation on the appliance database.** Never `rm` files under `/storage/seat`, `/storage/db`, `/storage/log`. Use purge scripts, SQL `TRUNCATE`/`VACUUM`, or space expansion only.
3. **Never delete delta/redo (`*-00000N.vmdk`), `-flat.vmdk`, `.ctk`, or `.vswp` files manually.** The chain may hold the only copy of the newest data.
4. **Never force-release a VM lock** without proving that the VM is not running on the host that owns the lock (see B1 step 3).
5. **`voma` and any datastore-metadata repair require Broadcom involvement** (advfix) plus a validated restore point. This is a STOP condition.
6. **Never revert a snapshot on one node of an Enhanced Linked Mode pair.**
7. **Disabling vSphere HA admission control is an emergency change with an expiry.** It must be re-enabled and recorded (see B4).
8. **Read the on-screen menu, not a memorized number.** Interactive tools (`certificate-manager`, `vCert`) renumber options between releases.
9. **One variable at a time.** Do not bundle certificate work with storage work; use separate change windows.
10. **Document as you go.** Record every command, output, timestamp, and decision in the incident record (Appendix F) — this is what makes an SOP auditable and an RCA possible.

---

## 7. Standard Diagnostic Toolkit

### 7.1 VCSA — service and platform health

| Purpose | Command |
|---|---|
| Service list/state | `service-control --status --all` |
| Start/stop one service | `service-control --stop vmware-vpxd && service-control --start vmware-vpxd` |
| Start/stop all | `service-control --stop --all && service-control --start --all` |
| Enumerate service names (release-specific) | `service-control --status --all` / `vmon-cli --list` |
| Certificate-manager (VMCA) utility | `/usr/lib/vmware-vmca/bin/certificate-manager` |
| Certificate store inventory (all stores, all expiry dates) | `for store in $(/usr/lib/vmware-vmafd/bin/vecs-cli store list \| grep -v TRUSTED_ROOT_CRLS); do echo "[*] Store :" $store; /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store --text \| grep -ie "Alias" -ie "Not After"; done;` |
| Single store detail | `/usr/lib/vmware-vmafd/bin/vecs-cli entry list --store MACHINE_SSL_CERT --text` |
| Machine ID / SSO site info | `/usr/lib/vmware-vmafd/bin/vmafd-cli get-machine-id --server-name localhost` |
| VMDIR health (L3 only, with backup) | `lsdoctor` tool (path varies by build; see Broadcom KB on `lsdoctor`) |
| Disk usage of all partitions | `df -h; df -i` |
| Largest directories | `du -sh /storage/* \| sort -h; du -sh /var/log/vmware/* \| sort -h` |
| VCDB client | `/opt/vmware/vpostgres/current/bin/psql -U postgres -d VCDB` |
| Support bundle | VAMI (5480) → **Support** → *Generate support bundle*, or the `vc-support` utility on the appliance (confirm path with `--help` on your build) |

### 7.2 ESXi host

| Purpose | Command |
|---|---|
| Version/build | `esxcli system version get`, `vmware -v` |
| Running VMs and their world/Cartel IDs | `esxcli vm process list`, `vim-cmd vmsvc/getallvms` |
| Datastores and devices | `esxcli storage filesystem list`, `esxcli storage core device list` |
| Path state (APD/PDL evidence) | `esxcli storage core path list`, `esxcli storage core device list -d naa.xxx` |
| Lock ownership on a file | `vmfsfilelockinfo -p /vmfs/volumes/<ds>/<vm>/<file>` |
| Lock owner *host MAC* (VMFS) | `vmkfstools -D /vmfs/volumes/<ds>/<vm>/<vm>-flat.vmdk` |
| Which process holds a file | `lsof \| egrep 'Cartel\|<file>'` |
| Snapshot chain inspection | `vmkfstools -q -v 10 /vmfs/volumes/<ds>/<vm>/<vm>.vmdk` |
| Chain/consistency check | `vmkfstools -e /vmfs/volumes/<ds>/<vm>/<disk>.vmdk` |
| Restart management agents (hostd/vpxa) | `services.sh restart` |
| Performance, interactive | `esxtop` (keys: `c` CPU, `m` memory, `d` disk, `v` VM view, `f` field selection) |
| On-disk metadata analyzer | `voma -m vmfs -f check -d /vmfs/devices/disks/naa.<id>:1` — **L3/Broadcom only** |
| Support bundle | `vm-support -w /vmfs/volumes/<healthy_ds>` |

### 7.3 vCenter log map

| Component | Path on VCSA |
|---|---|
| vpxd (core) | `/var/log/vmware/vpxd/vpxd.log` (rotated to `/storage/log/vmware/vpxd/`) |
| vSphere Client / UI | `/var/log/vmware/vsphere-ui/logs/` |
| Certificate manager / VMCA | `/var/log/vmware/vmcad/certificate-manager.log`, `/var/log/vmware/vmcad/vmcad.log` |
| SSO / identity (STS) | `/var/log/vmware/sso/`, `/var/log/vmware/sts/` |
| vmafd (directory lookups) | `/var/log/vmware/vmafpd/`, `/var/log/vmware/vmdird/` |
| Services framework | `/var/log/vmware/vmon/` |
| Appliance management / backup | `/var/log/vmware/applmgmt/` (`backup.log`, `vami.log`) |
| VCHA | `/var/log/vmware/vcha/` |
| vPostgres (VCDB) | `/var/log/vmware/vpostgres/` (path/format varies by build) |
| ESXi host HA agent (FDM) | `/var/log/fdm.log` on the ESXi host |
| ESXi host core logs | `/var/log/vmkernel.log`, `/var/log/hostd.log`, `/var/log/vpxa.log` (symlinked to `/var/run/log` when no persistent scratch) |

---

## 8. Standard Incident Workflow

```
  ┌────────────┐   ┌───────────┐   ┌──────────────┐   ┌───────────────┐
  │ 1. DETECT  │──▶│ 2. TRIAGE │──▶│ 3. STABILIZE │──▶│ 4. EVIDENCE   │
  │ Alert/User │   │ Which SOP │   │ Stop the     │   │ Logs, cmds,   │
  │            │   │ A#/B#?    │   │ bleeding     │   │ outputs, text │
  └────────────┘   └───────────┘   └──────────────┘   └───────┬───────┘
                                                              │
  ┌────────────┐   ┌───────────┐   ┌──────────────┐   ┌───────▼───────┐
  │ 8. CLOSE   │◀──│ 7. VERIFY │◀──│ 6. REMEDIATE │◀──│ 5. SAFEGUARD  │
  │ & PIR      │   │ Pass/fail │   │ Per SOP      │   │ Snapshot/BKP  │
  │            │   │ checks    │   │ steps        │   │ + Approval    │
  └────────────┘   └───────────┘   └──────────────┘   └───────────────┘
```

**Step 1 — Detect.** Alert from monitoring (Appendix D), user report, or Broadcom proactive notification.
**Step 2 — Triage.** Use the symptom matrix in §9 to select the SOP. Record the exact error text verbatim.
**Step 3 — Stabilize.** If the impact is growing (e.g. SEAT disk filling), apply the least-invasive containment step first (see each SOP's *Immediate containment* section). Containment must not destroy evidence.
**Step 4 — Evidence.** Run the *Evidence collection* block of the selected SOP. Save outputs to the incident record. For S1/S2, start the support bundle in parallel (it takes time).
**Step 5 — Safeguard.** Create the rollback point (snapshot per §5.4, or confirm a recent validated file-based backup), obtain change approval for the specific action, then proceed. Never skip this to "save time" in Part A.
**Step 6 — Remediate.** Execute the SOP steps in order. Honour every **STOP** condition: stop, escalate to L3/Broadcom, do not improvise.
**Step 7 — Verify.** Use the SOP's *Verification* checklist (pass/fail). A task that shows "Completed" is not verification.
**Step 8 — Close.** Update the incident record, remove temporary settings (admission-control disables, disabled alarms, temporary DRS overrides), schedule the prevention action, and hold a post-incident review for S1/S2.

---

## 9. Symptom → SOP Quick Reference Matrix

| # | Observed symptom | Most probable issue | SOP |
|---|---|---|---|
| 1 | vSphere Client: `[500] An error occurred while fetching identity providers`, login spinner, "Username and password are required" | Expired **STS / Solution User / Machine SSL** certificate | **A1** |
| 2 | `503 Service Unavailable`, `no healthy upstream`, VAMI shows `certificate verify failed: certificate has expired` | Expired certificate chain (Machine SSL / issuing CA) | **A1** |
| 3 | VAMI (5480) reachable but vSphere Client down; `service-control --status` shows `vmware-vpxd` **stopped** with "storage partition of Database exceeds threshold" | **`/storage/seat` exhaustion** | **A3** |
| 4 | Many services `Stopped`/`StartPending`; `service-control --start --all` fails; VMDIR/DNS/time errors | **Services fail to start** (VMDIR, DNS, time, cert, storage) | **A2** |
| 5 | Alarm "vCenter HA cluster state is currently **degraded / isolated**"; Passive node does not take over | **VCHA** failover/synchronization failure | **A4** |
| 6 | VAMI file-based backup fails: "Full backup not allowed during VM snapshot", "Broken pipe", "component vum backup" | **File-based backup** failure | **A5** |
| 7 | VM power-on fails: "Failed to lock the file", "Unable to access file ... since it is locked", "Lost previously held lock" | **VM file lock** | **B1** |
| 8 | VM Summary shows "**Virtual machine disks consolidation is needed**"; snapshot delete/consolidate fails | **Snapshot consolidation** | **B2** |
| 9 | vMotion fails at validation: "Host CPU is incompatible …", "The target host does not support the virtual machine's current hardware requirements", "VMotion interface is not configured" | **Migration/compatibility (EVC, network, device)** | **B3** |
| 10 | Power-on fails: "**Insufficient resources to satisfy configured failover level for vSphere HA**"; cluster banner "Insufficient configured resources to satisfy the desired vSphere HA failover level" | **HA admission control** | **B4** |
| 11 | VM slow, guest CPU idle, `%RDY` high, ballooning/swap, storage latency | **CPU ready / memory contention / storage latency** | **B5** |
| 12 | vCenter overall slow; UI timeouts; tasks queue | Cross-check A2 (service health, DB size), A3 (SEAT/log/db), B5 methodology for host-level contention |

---
---

# PART A — vCenter Platform / Feature Issues

---

## A1. Expired Certificates Block vCenter (STS / Machine SSL / Solution User / Issuing CA)

| Attribute | Detail |
|---|---|
| SOP ID | **A1** |
| Default severity | **S1** (complete loss of vCenter management) |
| Frequency | Common — the single most frequent cause of "vCenter is dead" |
| Typical MTTR | 1–3 h (standalone), 3–6 h (Enhanced Linked Mode, once per node) |
| Downtime | None required as a planned action; **outage already exists** in the unplanned case |
| Skills | L2 + L3 (L3 mandatory for ELM and custom-CA environments) |
| Change required | Yes — planned renewal; Emergency change if already expired |

### A1.1 Trigger and symptoms

vCenter authentication depends on four certificate layers. When any of them is invalid, the dependency chain collapses and services stop or refuse connections:

| Certificate | Used by | Validity (VMCA-signed, typical) | Failure symptom |
|---|---|---|---|
| **STS signing certificate** | SSO signs SAML tokens | ~2 years (10 years on some fresh deployments) | Cannot log in at all; new logins fail; inter-service calls fail |
| **Solution User certificates** (machine, vsphere-webclient, vpxd, vpxd-extension, hvc) | Services authenticate to STS | ~2 years | Services stop / `StartPending`; `[500] fetching identity providers` |
| **Machine SSL certificate** | Port 443 / reverse proxy, service-to-service TLS | ~2 years (leaf validity capped by CA/B Forum) | `503 Service Unavailable`, `no healthy upstream` |
| **Issuing/internal CA in `TRUSTED_ROOTS`** | Trust anchor for the above | CA-dependent | Services fail to start even though the **leaf is still valid** |

Common observed errors (copy verbatim into the incident record):

* Browser: `503 Service Unavailable`, `no healthy upstream`, `[500] An error occurred while fetching identity providers. Try again.`, `Username and password are required`.
* VAMI (5480): `[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: certificate has expired`.
* vSphere Client: `503 Service Unavailable (Failed to connect to endpoint: [N7Vmacore4Http20NamedPipeServiceSpecE:...] _pipeName =/var/run/vmware/vpxd-webserver-pipe)`.
* `service-control --status --all`: `vmware-vpxd`, `vmware-vpxd-svcs`, `vmware-sps` (and others) `Stopped` or `StartPending`.
* `/var/log/vmware/vpxd/vpxd.log`: `warning vpxd[...] [opID=CheckCertificateExpiry] Certificate [Subject: CN=...] from store TRUSTED_ROOTS will expire on YYYY-MM-DD`.
* SSO/STS logs: `Signing certificate is not valid`.
* Known quirk: on some 8.0.x builds, an expired certificate can lock the **root account** for SSH ("password not accepted") while console login works; resetting the root password from the virtual console restores SSH access.

### A1.2 Impact

* Total loss of vCenter management — no VM operations, no alarms/tasks, no DRS/HA reconfiguration; backup jobs that depend on vCenter fail.
* Running workloads are **not** interrupted (ESXi hosts keep VMs running), which is why certificate expiry is often discovered late.
* Blast radius in Enhanced Linked Mode (ELM): all linked nodes share STS/SSO. A partial fix leaves the SSO domain inconsistent.

### A1.3 Root causes (ranked)

1. No certificate expiry monitoring or renewal calendar (dominant cause).
2. STS/solution-user certificates have a shorter validity than the Machine SSL certificate; the 2-year clock is forgotten after a vCenter upgrade (upgrades **carry forward** the old STS certificate).
3. Machine SSL certificate replaced with a custom CA certificate whose **issuing/root CA later expired** — trust breaks even though the leaf is valid.
4. Certificate replaced in a lab/test procedure that skipped one store or one node.
5. Severe time skew (NTP failure) causing valid certificates to be evaluated as expired/not-yet-valid.

### A1.4 Pre-checks (do these before touching anything)

1. **Confirm the clock:** `date; timedatectl status; chronyc sources` (or `ntpq -p`). Fix time/NTP first — never renew certificates on a skewed appliance.
2. **Confirm you can log in.** Test `root` over SSH *and* the virtual console. If SSH is refused, use the VCSA console (`Alt+F1` to switch to the shell, `Alt+F2` to return) and reset the root password if required.
3. **Confirm you have `administrator@vsphere.local`** credentials and that the account is not locked/expired. If SSO admin access is lost, `certificate-manager` options that require SSO credentials will fail — escalate to L3/Broadcom immediately (**STOP**).
4. **Snapshot per §5.4.** ELM: **power off all nodes and take offline snapshots of every node.** Standalone: snapshot from the ESXi host client (not from vCenter, which is down).
5. **Record the current state (evidence):**
   ```bash
   service-control --status --all | tee /root/incident-$(date +%F)-services.txt
   df -h; df -i
   tail -200 /var/log/vmware/vpxd/vpxd.log
   ```
6. **Inventory every certificate and its expiry date:**
   ```bash
   for store in $(/usr/lib/vmware-vmafd/bin/vecs-cli store list | grep -v TRUSTED_ROOT_CRLS); do
     echo "[*] Store :" $store
     /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store --text | grep -ie "Alias" -ie "Not After"
   done;
   ```
   Record which stores are expired vs. valid. This determines whether you renew one item, several, or all.
7. **Determine whether custom CA certificates are in use.** If any store holds a non-VMCA certificate you **must** have the issuing chain available and plan to re-import it (A1.9). Record the current thumbprints before replacing anything.

### A1.5 Decision tree

```
Certificate inventory collected
|
+-- All certificates valid, but some expire within 60 days (planned work)?
|      --> A1.6 PATH 1 - Planned renewal
|
+-- STS and/or Solution User certificates EXPIRED (login/SSO broken, services stopped)?
|      --> A1.7 PATH 2 - Replace expired STS / Solution User certificates
|
+-- Machine SSL certificate EXPIRED (503 / no healthy upstream)?
|      --> A1.8 PATH 3 - Replace the Machine SSL certificate
|
+-- Multiple stores affected, or the issuing CA expired, or state unclear?
       --> A1.9 PATH 4 - Reset all certificates with VMCA-signed certificates
```

> **Menu numbering caveat.** `certificate-manager` and `vCert` menus change between releases. The option **labels** below are stable; the numbers are not. Always read the on-screen menu.

### A1.6 PATH 1 — Planned renewal (nothing expired yet)

1. Schedule a maintenance window (no downtime expected, but services restart).
2. In the vSphere Client verify current state: **Administration → Certificate Management → Certificate Status** (expected: "All certificates are valid").
3. Use the built-in renewal first (it re-issues the Machine SSL certificate only):
   **Administration → Certificate Management → Machine SSL Certificate → Actions → Renew**.
   *Alternative (CLI):* `/usr/lib/vmware-vmca/bin/certificate-manager` → *Replace Machine SSL certificate with VMCA Certificate* (option **3** in recent releases).
4. Renew **STS / Solution User** certificates with the **vCert** tool (Broadcom KB 385107) — recommended for 7.x/8.x:
   * Upload `vCert-<version>.zip` to `/root` on the appliance, unzip it, `cd` into the directory, run `./vCert.py`.
   * Menu **1 — Check current certificate status** (confirm what will change).
   * Menu **3 — Manage certificates**.
   * Solution User certificates: **3 → 2 — Solution User certificates** → **1 — Replace with VMCA signed certificates**.
   * STS: choose the STS/signing-certificate option (label: *Replace / regenerate the STS signing certificate*) and follow the prompts.
5. Restart services: `service-control --stop --all && service-control --start --all`.
   *If the first start pass partially fails, re-run `service-control --start --all` — the STS/SSO chain often needs a second pass.*
6. Verify (A1.10), then plan the **custom-CA re-import** (if applicable) as a follow-up change.

### A1.7 PATH 2 — Expired STS / Solution User certificates (login broken)

1. Snapshot per §5.4 (offline snapshots for all ELM nodes).
2. Preferred tool: **vCert** (menu *3 Manage certificates → 2 Solution User certificates → 1 Replace with VMCA*). Broadcom's expired-Solution-User-certificate article documents exactly this path, including taking offline snapshots and repeating on each ELM appliance.
3. Built-in alternative: `/usr/lib/vmware-vmca/bin/certificate-manager` → select the option labelled *Replace Solution user certificates with VMCA certificates* (numbering has appeared as both 4 and 6 across releases).
4. For an expired **STS signing certificate**, select the STS option in the same tool (label: *Replace / regenerate the STS signing certificate*). On legacy 6.5/6.7, `fixsts.sh` (KB 76719) was the documented method; Broadcom now directs customers to `certificate-manager` or vCert.
5. Restart all services; expect to run the start command twice, and note that Broadcom's article warns service start may fail and require manual re-initiation:
   ```bash
   service-control --stop --all
   service-control --start --all
   service-control --status --all        # re-run the start command if any core service is StartPending
   ```
6. Verify login (A1.10). If login still fails with SSO errors after all certificates show valid, stop and escalate to L3/Broadcom — VMDIR/SSO state may need the `lsdoctor` tool (KB-governed, L3 only).

### A1.8 PATH 3 — Expired Machine SSL certificate (`503` / `no healthy upstream`)

1. Snapshot per §5.4.
2. Fastest trusted recovery — replace with a VMCA-signed certificate:
   `/usr/lib/vmware-vmca/bin/certificate-manager` → *Replace Machine SSL certificate with VMCA Certificate* (option **3** in recent releases). Supply the SSO administrator credentials and appliance details at each prompt.
3. If the 503 is caused by an **IP-address mismatch** inside the Machine SSL certificate (documented Broadcom article "503 Service Unavailable … due to Machine SSL IP address mismatch"), regenerate the certificate with the correct FQDN/IP SANs — use *Replace Machine SSL certificate with Custom Certificate* (CSR flow) or vCert *3 → 1 → custom CA-signed*.
4. If the certificate was signed by an **expired issuing/root CA**, the trust anchor must be replaced before services start: restore service with a VMCA-signed certificate (step 2), then import the renewed external CA chain (A1.9 step 4) as a follow-up change.
5. Restart services (`service-control --stop --all && service-control --start --all`), then verify (A1.10).

### A1.9 PATH 4 — Reset all certificates with VMCA-signed certificates

Use when several stores are affected, when the failing layer is unclear, or to restore service urgently before re-importing custom certificates.

1. Snapshot per §5.4 (offline for ELM). **Write down the current thumbprints** for any custom certificates before resetting — you will need them afterwards.
2. Built-in utility: `/usr/lib/vmware-vmca/bin/certificate-manager` → **Reset all Certificates** (option **8** in recent releases). Supply the SSO administrator password and the required details (FQDN, IP, hostname) at each prompt.
   *Alternatively with vCert:* main menu **3 → 6 — Reset all certificates with VMCA-signed certificates**.
3. Restart services (expect to start twice):
   ```bash
   service-control --stop --all
   service-control --start --all
   service-control --status --all
   ```
4. **Re-import custom CA certificates (if applicable)** with vCert:
   * **3 → 1 — Machine SSL certificate** → custom CA-signed option → generate key + CSR → sign externally → import certificate + full chain.
   * **3 → 3 — CA certificates in VMware Directory** → publish the renewed root/intermediate.
   * **4 → 2 — Update SSL Trust Anchors**.
   * **8 → 1 — Restart all VMware services**.
   * Verify with menu **1** (no expired certificates, no trust problems).
5. **In ELM:** repeat the procedure on **each** appliance, and note that if multiple vCenters have expired solution-user certificates they must each be renewed.
6. After a reset, VMCA-signed certificates typically show a **10-year** validity (vs. 2 years for renewed ones). Verify in **Administration → Certificate Management**.

### A1.10 Verification of recovery (pass/fail)

| # | Check | Pass criterion |
|---|---|---|
| V1 | `service-control --status --all` | All core services `Running`; no `StartPending` |
| V2 | `vecs-cli` store loop (A1.4 step 6) | No certificate with a past `Not After` date |
| V3 | VAMI `https://<vcsa>:5480` | Login page loads without TLS errors; certificate has > 60 days validity |
| V4 | vSphere Client `https://<vcsa>/ui` | Login succeeds as `administrator@vsphere.local` **and** with an AD user if AD is configured |
| V5 | Administration → Certificate Management | "All certificates are valid"; no trust warnings |
| V6 | Inventory health | Hosts `Connected`; tasks and events resume updating |
| V7 | `tail /var/log/vmware/vpxd/vpxd.log` | No new `CheckCertificateExpiry` / STS errors in the last 15 minutes |
| V8 | SSO login test | Log out and log in again (proves STS issued a fresh, valid token) |

### A1.11 Rollback / backout

| Situation | Action |
|---|---|
| Certificate replacement made things worse | Revert the offline snapshot (**ELM: power off all nodes first**, then revert each node to the same point in time). A partial revert in ELM causes VMDIR replication divergence — this is why §5.4 S-3 exists |
| Custom certificates were lost/overwritten | Restore from the thumbprint/CSR archive; if unavailable, remain on VMCA-signed certificates and rebuild the custom chain from the issuing CA |
| SSO admin account unusable mid-procedure | Stop; restore the snapshot; engage L3/Broadcom (do not attempt repeated blind resets) |
| Root password locked (8.0.x quirk) | Reset the root password from the virtual console, then restart the procedure |

### A1.12 Prevention (mandatory actions after closure)

1. **Automated expiry monitoring.** Weekly job running the `vecs-cli` loop on every vCenter node; alert if any `Not After` is < 60 days (warn) / < 30 days (critical). Include the appliance's **own** CA chain, not just leaves.
2. **Dashboard/alarm.** Enable and route the *Expired CA Certificates Remain in the VECS Trusted Root Store* alarm and vCenter certificate-expiry alarms to the on-call queue.
3. **Calendar the 2-year cycle.** After every deployment or upgrade, record the STS and Solution User certificate expiry dates in the asset register. vCenter **upgrades carry forward** the STS certificate — the clock does not reset.
4. **NTP compliance.** Alert if NTP offset > 1 s or if no source is synced.
5. **ELM register.** Maintain a list of nodes in the SSO domain; the renewal runbook must state "repeat on every node".
6. **Annual dry run.** In the lab, execute A1.9 end to end — including custom-CA re-import — and time it.
7. **Upgrade pre-check.** Before any vCenter upgrade, run the certificate inventory and renew anything expiring within 90 days.

### A1.13 Anti-patterns (do not do these)

* Renewing on one ELM node and leaving the others expired.
* Reverting a snapshot on one node of an ELM pair.
* Replacing certificates while an **external CA leaf is still in place** without recording its thumbprint and chain.
* Skipping the snapshot because "the appliance is already broken" — the snapshot is what allows recovery from a bad reset.
* Editing `vmdir`/`vecs` stores by hand instead of using supported tools.
* Assuming the Machine SSL certificate was the only problem when services also use STS and Solution User certificates.

### A1.14 References

* Broadcom KB **82332** — `"no healthy upstream"` or `"503 Service Unavailable"` when accessing vCenter Server (STS/Machine SSL/Solution User expiry; includes the `vecs-cli` inventory loop and the reset options).
* Broadcom KB **421381** — Unable to access vCenter Server due to expired **Solution User** certificates (vCert path; offline snapshots; repeat per appliance).
* Broadcom KB **442815** — vCenter services fail to start after the Machine SSL certificate's **issuing CA expires** (two-part VMCA recovery, then re-import custom certificates/trust anchors).
* Broadcom KB **399590** — "503 Service Unavailable" due to Machine SSL **IP address mismatch**.
* Broadcom KB **420242** — vCenter STS certificate will not renew (custom CA in solution users/STS; reset-all remedy and 10-year verification).
* Broadcom KB **318946** — Using vSphere Certificate Manager to replace SSL certificates.
* Broadcom KB **385107** — **vCert** — vCenter certificate replacement script (download + menu map).
* Broadcom KB **76719** — legacy: regenerating/replacing the expired STS certificate with the shell script (6.5/6.7 only).
* Broadcom KB **2112283** — renewing/regenerating vCenter certificates (general procedure).
* Broadcom TechDocs — *Managing certificates with the vSphere Certificate Manager utility* (reset-all-certificates procedure).

---

## A2. vCenter Appliance Services Fail to Start (vSphere Client Unavailable, VAMI Reachable)

| Attribute | Detail |
|---|---|
| SOP ID | **A2** |
| Default severity | **S1** |
| Frequency | Common |
| Typical MTTR | 30 min – 4 h |
| Downtime | Service restart (short; the unplanned outage is already in effect) |
| Skills | L2; L3 for VMDIR / `lsdoctor` work |
| Change required | Emergency change (service restart); planned change if an appliance reboot is required |

### A2.1 Trigger and symptoms

* vSphere Client returns `503 Service Unavailable` / `no healthy upstream`, or the login page loads but never completes.
* VAMI (`:5480`) is reachable, but the service list shows multiple services `Stopped` or `StartPending`.
* `service-control --start --all` returns a failure such as `Failed to start <service>` / `Service-control failed. Error Failed to start vmon services.`
* `/var/log/vmware/vmon/*.log` shows dependency problems or restart loops; individual service logs (`/var/log/vmware/<service>/`) contain the underlying exception.
* Sometimes limited to one component: `vmdird` (directory), SSO/STS, `vmware-vpostgres`, `vmware-vpxd`, `vmware-vapi-endpoint`, `vmware-content-library`, `vmware-updatemgr`.

### A2.2 Impact

Varies with the failing set — from a single broken feature (e.g. Update Manager) to a total loss of vCenter management. If `vmware-vpxd` or the identity/directory services are down, treat as **S1**.

### A2.3 Root causes (ranked)

1. **Certificate problems** — see **A1** (the single most common cause; always rule it out).
2. **Storage exhaustion** on `/storage/log`, `/storage/db`, `/storage/core`, `/storage/seat` — see **A3**.
3. **Directory (VMDIR) replication state damage** — often pre-existing, surfaced by a reboot; replication/first-instance conflict errors in logs.
4. **DNS / hostname mismatch** — forward or reverse lookup of the appliance FQDN fails or returns another host; DNS changes after deployment break inter-service TLS.
5. **Time skew (NTP)** — breaks Kerberos/SSO and certificate validation.
6. **vPostgres not running / WAL or connection problems** — vpxd depends on the database.
7. **Appliance resource starvation** (host CPU/memory contention, stopped ESXi host) or a vCenter VM that was **cloned or re-IP'd**.
8. **Service startup policy changed/disabled**, or a failed update left a component inconsistent.
9. **8.0.x root-account lockout** after certificate expiry (see A1).

### A2.4 Evidence collection (before any restart attempt)

```bash
# 1. Current state and history of attempts
service-control --status --all | tee /root/inc-$(date +%F-%H%M)-services.txt
journalctl -u vmware-vmon --since "2 hours ago" > /root/inc-$(date +%F-%H%M)-vmon.txt 2>/dev/null || tail -500 /var/log/vmware/vmon/*.log > /root/inc-$(date +%F-%H%M)-vmon.txt

# 2. Storage and time
df -h; df -i
timedatectl status

# 3. Name resolution (all three must agree)
hostname -f; getent hosts "$(hostname -f)"; getent hosts "$(hostname -s)"; cat /etc/hosts; cat /etc/resolv.conf

# 4. Certificate sanity (full loop is in A1.4 step 6)
for store in $(/usr/lib/vmware-vmafd/bin/vecs-cli store list | grep -v TRUSTED_ROOT_CRLS); do
  echo "[*] Store :" $store
  /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store --text | grep -ie "Alias" -ie "Not After"
done;

# 5. Service-specific logs - pick the failing service(s)
tail -200 /var/log/vmware/vpxd/vpxd.log
tail -200 /var/log/vmware/vmdird/vmdird-syslog.log 2>/dev/null
tail -200 /var/log/vmware/sts/sts.log 2>/dev/null
tail -200 /var/log/vmware/vmafpd/vmafpd.log 2>/dev/null
```

| Evidence pattern | Likely root cause | Go to |
|---|---|---|
| Expired `Not After` in any store | Certificate expiry | **A1** |
| Any `/storage/*` at 100% (or `df -i` inodes exhausted) | Storage exhaustion | **A3** |
| `getent hosts` fails or returns the wrong IP | DNS/hostname mismatch | A2.6 step 3 |
| NTP not synced / large offset | Time skew | A2.6 step 2 |
| VMDIR replication / first-instance errors | Directory state | A2.6 step 5 (L3 only) |
| `vpostgres` stopped, `could not connect to server`, WAL errors | VCDB problem | A2.6 step 4 |
| No clear error, service `StartPending` | Stuck service / dependency | A2.6 step 1 |

### A2.5 Immediate containment

1. **Do not reboot repeatedly.** Each reboot without evidence destroys the state needed for RCA and can worsen VMDIR problems.
2. Start the support bundle now (it takes time and is required for both RCA and Broadcom support): VAMI → **Support** → *Generate support bundle*, or the `vc-support` utility on the appliance.
3. If only one non-critical service is down (e.g. Update Manager) and vCenter is otherwise healthy, note it, schedule a maintenance window and continue with A2.6.
4. Communicate impact per §4 — vCenter may be partially or fully unusable.

### A2.6 Resolution procedure

**Step 1 — Attempt a controlled restart of the failed service(s).**

```bash
service-control --stop vmware-vpxd && service-control --start vmware-vpxd    # single service example
# or, when several are affected:
service-control --stop --all && service-control --start --all
service-control --status --all
```
Expected: services transition to `Running`. If a service stays `StartPending` for more than 5 minutes, continue.

**Step 2 — Fix time skew (if present), then retry.**
```bash
timedatectl status
chronyc sources            # or: ntpq -p
systemctl restart chronyd  # or: ntpd
timedatectl set-ntp true
```
Certificate validation depends on accurate time; re-run step 1 afterwards.

**Step 3 — Fix DNS/hostname mismatch (if present), then retry.**
* The appliance FQDN must resolve **forward and reverse** to its IP, and `/etc/hosts` must be consistent with DNS.
* If DNS was changed after deployment, restore the correct record or add a correct `/etc/hosts` entry.
* Confirm that ESXi hosts and admin workstations resolve the FQDN identically.
Then repeat step 1.

**Step 4 — Verify vPostgres and start dependencies in order (if the database is implicated).**
```bash
service-control --status vmware-vpostgres
service-control --start vmware-vpostgres
service-control --start vmware-vpxd
service-control --start vmware-vpxd-svcs 2>/dev/null
```
Database corruption, WAL problems, or a full `/storage/db` → **A3**, and escalate to L3/Broadcom if the database will not come up cleanly.

**Step 5 — Directory (VMDIR) state — L3 ONLY, with a snapshot in place.**
If logs show replication conflicts, first-instance problems, or `Unable to bind to LDAP`, escalate to L3. The `lsdoctor` tool (Broadcom KB-governed) can detect and repair many VMDIR inconsistencies: run the **read-only check first**, snapshot immediately before any repair, and never improvise directory fixes.

**Step 6 — Last resort: reboot the appliance (with discipline).**
1. Take a snapshot (offline for ELM; see §5.4 S-3/S-4).
2. Reboot via `shutdown -r now` (SSH), VAMI, or the host client.
3. Wait 10–15 minutes after the UI responds, then re-check `service-control --status --all`.
4. **Remove the snapshot within 24 h** once verified healthy.
5. Record the reboot, snapshot removal, and verification evidence in the change record.

**Step 7 — If a service still will not start after steps 1–6: STOP.**
Raise a Broadcom SR (Severity 1) with: the support bundle, `service-control --status --all` output, the specific service log, a timeline, recent change history (patches, DNS, certificate work), and the outputs from steps 1–6. Do **not** disable services or hand-edit configuration to force a start.

### A2.7 Verification of recovery

| # | Check | Pass criterion |
|---|---|---|
| V1 | `service-control --status --all` | Every service `Running` for 15+ minutes (no restart loop) |
| V2 | vSphere Client login | Succeeds for SSO and AD users |
| V3 | VAMI | All health indicators green; no active alerts |
| V4 | Inventory | All hosts `Connected`; VMs show current state; no "not responding" hosts |
| V5 | Activity | New tasks/events appear (proves the vpxd → VCDB write path) |
| V6 | Feature spot-checks | vMotion a test VM, take and delete a snapshot, open Update Manager, run a cluster compliance check |
| V7 | Backups | The next scheduled file-based backup runs (cross-check **A5**) |

### A2.8 Rollback

| Situation | Action |
|---|---|
| Restart made it worse (more services stopped) | Capture logs, then revert the snapshot; if no snapshot exists, escalate to Broadcom immediately with the bundle |
| Appliance reboot did not resolve it | Do **not** reboot again. Restore the most recent validated file-based backup into a new appliance (A5.8) or engage Broadcom — in that order, with business approval |
| A DNS change was the trigger | Restore the previous DNS configuration, re-test, and document the record change |

### A2.9 Prevention

1. **Monitor service state** (parse `service-control --status --all` weekly, or use the built-in vCenter Server health alarms) and alert on any non-`Running` core service.
2. **Monitor appliance storage** (A3 thresholds) — most "service will not start" events in practice are storage events.
3. **Enforce NTP** on the appliance and on ESXi hosts; alert on sync loss.
4. **Freeze DNS records** for vCenter (change control required) and document forward/reverse entries in the CMDB.
5. **Never clone or re-IP a deployed VCSA** outside the supported re-IP procedure; cloning an appliance is unsupported and produces exactly this symptom class.
6. **Patch cadence** — apply vCenter updates on a schedule; many service-start defects are fixed in updates.
7. **Post-change health check** after every vCenter patch, DNS change, or firewall change: service status + client login + one VM operation.

### A2.10 References

* Broadcom KB **82332** — 503 / no healthy upstream (rule out certificates first).
* Broadcom KB **318931**, **390417** — SEAT/partition exhaustion causing services to stop.
* Broadcom KB — *vCenter Server services fail to start* (search the KB portal using the exact service name in your error).
* Broadcom TechDocs — *vCenter Server Appliance service management* (`service-control`, `vmon`).
* Broadcom KB — `lsdoctor` tool article (VMDIR checks/repairs; L3 only).

---

## A3. Appliance Storage Exhaustion — `/storage/seat`, `/storage/db`, `/storage/log`, `/storage/core`

| Attribute | Detail |
|---|---|
| SOP ID | **A3** |
| Default severity | **S1** (vpxd refuses to start past the hard threshold) |
| Frequency | Very common |
| Typical MTTR | 1–3 h (space reclamation) plus a capacity change for the permanent fix |
| Downtime | vpxd stopped during reclamation (management outage; VMs unaffected) |
| Skills | L2 executes; L3 approves database-truncation scope |
| Change required | Yes (Emergency change if vpxd is already stopped) |

### A3.1 Partition roles (know which one is full)

| Mount | Contains | Symptom when full |
|---|---|---|
| `/storage/seat` | **VCDB** (vPostgres data directory: events, tasks, statistics) | vpxd shuts itself down at the 95% threshold to protect the database; vSphere Client down |
| `/storage/db` | vPostgres **WAL**, system databases, runtime instance (layout varies by version) | vPostgres will not start; vpxd cannot connect; similar failure mode |
| `/storage/log` | Rotated/archived logs (and a common target for log bombs) | Logging stops; some services fail to start |
| `/storage/core` | Core dumps, support bundles, backup history/schedule JSON | Space alerts; failed support-bundle generation |
| `/storage/archive` | Update Manager / appliance archive data | Update-related failures |

Typical log signature (`/var/log/vmware/vpxd/vpxd.log`) when SEAT crosses the threshold:

```
info  vpxd[...] [Originator@6876 sub=vpxdVdb] WarningThreshold: 80% ErrorThreshold: 95%.
error vpxd[...] [Originator@6876 sub=vpxdVdb] Space used on storage partition of Database exceeds
      threshold (used: 95%; threshold: 95%). Service-control request will stop vpxd
info  vpxd[...] [Originator@6876 sub=vpxdvpxdSignal] Signal 15 received, exiting
info  vpxd[...] [Originator@6876 sub=Default] Initiating VMware VirtualCenter shutdown
```

### A3.2 Impact

* vSphere Client unavailable (vpxd stopped); VAMI still usable; **VMs keep running** on the hosts.
* No VM operations, no alarms firing, no DRS/HA actions.
* Risk of **database corruption** if space is reclaimed incorrectly (deleting files, killing vPostgres mid-write).

### A3.3 Root causes (ranked)

1. **Event/task storm** from one or two ESXi hosts — classic examples: repeated hardware-health / "Sensor -1 type" alarms, a host repeatedly disconnecting and reconnecting, syslog storms, or (in 8.x) load-balancer/login event floods tied to a Supervisor/AVI component.
2. **Statistics level left at 3–4** on a large inventory — `vpx_hist_stat*` tables dominate growth.
3. **Purge/cleanup stalled** (failed autovacuum, service restart loops) — rows grow beyond the retention window.
4. **No retention tuning** — default event/task retention too long for the inventory and disk size.
5. **Undersized appliance for the inventory** (SEAT partition sized for fewer VMs).
6. **Log flood filling `/storage/log`** (chatty service, repeated failed-task logging, debug logging left enabled).
7. **Core dumps / old support bundles never cleaned** (`/storage/core`).

### A3.4 Evidence collection

```bash
# 1. Which partition, how full, how fast
df -h; df -i
du -sh /storage/* | sort -h
du -sh /var/log/vmware/* 2>/dev/null | sort -h | tail -20

# 2. Confirm the vpxd threshold event
grep -i "storage partition of Database" /var/log/vmware/vpxd/vpxd.log | tail -20

# 3. Service state
service-control --status --all

# 4. Connect to the database (VCDB) for table-level evidence
/opt/vmware/vpostgres/current/bin/psql -U postgres -d VCDB
```
```sql
-- 4a. Largest event/task/statistics tables
SELECT table_name,
       pg_size_pretty(pg_total_relation_size(quote_ident(table_name))) AS size
FROM information_schema.tables
WHERE table_schema = 'vc'
  AND (table_name LIKE 'vpx_event%' OR table_name LIKE 'vpx_task%' OR table_name LIKE 'vpx_hist_stat%')
ORDER BY pg_total_relation_size(quote_ident(table_name)) DESC
LIMIT 20;

-- 4b. Which event type is storming?
SELECT event_type, count(*) AS c
FROM vc.vpx_event_1
GROUP BY event_type
ORDER BY c DESC
LIMIT 10;

-- 4c. Dead tuples / failed autovacuum indicator
SELECT relname, n_live_tup, n_dead_tup,
       round(100.0*n_dead_tup/greatest(n_live_tup+n_dead_tup,1),1) AS dead_pct
FROM pg_stat_user_tables
WHERE relname LIKE 'vpx%'
ORDER BY n_dead_tup DESC
LIMIT 20;

-- exit
\q
```
> Table names are version- and partition-dependent (`vpx_event_1`, …). Validate object names on your build before any data change (`\d+ vpx_event*`).

**Root-cause identification:** query 4b identifies *what* is generating volume; correlate with the vSphere Client Events view (filter by event type and time) to identify *which* host/VM/component. Fix that source, or the disk simply refills.

### A3.5 Immediate containment (least invasive first)

1. **Buy working space without touching data.** If the reserved headroom file exists (recommended practice), delete it:
   ```bash
   ls -lh /storage/seat/*.headroom     # e.g. /storage/seat/RESERVED.headroom, created with fallocate while healthy
   rm -f /storage/seat/RESERVED.headroom
   df -h /storage/seat
   ```
   If it does not exist, expand the disk (A3.6 step 7) — do **not** delete files.
2. **Reduce the input**: silence the storm source (fix/acknowledge the alarming host, disable the noisy alarm, stop the failing component) so the partition refills more slowly than you can remediate.
3. **Stop vpxd and content-library cleanly before any database work** (never let vPostgres be killed mid-write):
   ```bash
   service-control --stop vmware-vpxd
   service-control --stop vmware-content-library
   service-control --status vmware-vpxd vmware-content-library
   ```

### A3.6 Resolution procedure

**Step 1 — Use Broadcom's supported purge scripts (preferred).**
KB 2110031 publishes scripts that delete old **tasks, events, and statistics** data and reset the event sequence (for 7.0/8.x: the `_Postgres_task_event_stat_reset_event_sequence.sql` variant). With vpxd and content-library stopped, run the script against VCDB, then continue at step 5. This is the supported, auditable path.

**Step 2 — Or truncate the dominant event/task tables (vpxd stopped).**
```sql
-- in psql, connected to VCDB (vpxd + content-library stopped)
TRUNCATE TABLE vc.vpx_event_1 CASCADE;
-- repeat for the specific large tables found in evidence 4a, ONE AT A TIME:
--   TRUNCATE TABLE vc.vpx_event_arg_1 CASCADE;
--   TRUNCATE TABLE vc.vpx_task CASCADE;
\q
```
Rules:
* Truncate **one table at a time** and re-check `df -h` between statements.
* Only truncate the `vpx_event*` / `vpx_event_arg*` / `vpx_task*` class. **Never** touch inventory, alarm-definition, or host/VM configuration tables.
* If a statement fails with `ERROR: could not extend file ... No space left on device`, obtain working space first (step 7), then retry.
* Reclaim is gradual; very large tables may additionally need `VACUUM FULL` (exclusive lock, needs temporary space roughly equal to the table size → L3 + maintenance window).

**Step 3 — Address statistics-driven growth.**
vSphere Client → **vCenter Server → Configure → General → Statistics**: reduce **Statistics Level** (1 or 2) where the inventory cannot carry level 3, and confirm the `vpx_hist_stat*` tables stop growing in subsequent `df -h` samples.

**Step 4 — Tune retention (Advanced Settings).**
vCenter → **Configure → Advanced Settings** exposes event/task retention controls (for example `event.maxAge`, `event.maxAgeEnabled`, `task.maxAge`, `task.maxAgeEnabled`, plus cleanup-rate settings — names are release-specific; confirm in your build). Set a documented, supportable window (e.g. 30 days) and record old/new values in the change record.

**Step 5 — Restart services in order and verify vpxd stays up.**
```bash
service-control --start vmware-vpxd
service-control --start vmware-content-library
sleep 120; df -h /storage/seat; service-control --status vmware-vpxd
```

**Step 6 — Prevent immediate refill.**
Fix the storm source identified in evidence 4b (host hardware-sensor alarms, flapping host, failing service, AVI/Supervisor component) and add a vCenter alarm or monitoring rule so the same event type cannot repeat unseen.

**Step 7 — Permanent fix: expand the appliance disk.**
1. Once healthy, create a **reserved headroom file** so the next event is survivable:
   `fallocate -l 2G /storage/seat/RESERVED.headroom` (document it — it is intentional, not junk).
2. In a planned window, power off the VCSA, increase the virtual disk backing the affected partition (SEAT is commonly **Hard disk 8** — confirm the mapping in VAMI → Monitor → Disk first), power on, and let the appliance grow the LVM/partition using the supported *increasing disk space for the vCenter Server Appliance* procedure (legacy builds: `vpxd_servicecfg storage lvm autogrow`).
3. Verify with `df -h`. Partitions can be **extended but not shrunk**.

### A3.7 Verification of recovery

| # | Check | Pass criterion |
|---|---|---|
| V1 | `df -h` on the affected mount | < 70% used, trending flat or declining |
| V2 | `df -i` | Inodes < 70% used |
| V3 | `service-control --status --all` | `vmware-vpxd` and `vmware-content-library` `Running` for 30+ minutes |
| V4 | vSphere Client | Login succeeds; Events/Tasks views populate with new entries |
| V5 | Storm source | Root-cause event type no longer generated (re-run query 4b after 24 h; count near zero) |
| V6 | Growth rate | 24 h later, SEAT growth < ~100 MB/day on a stable inventory |
| V7 | Backup | A file-based backup completes after the change (cross-check **A5**) |

### A3.8 Rollback

| Situation | Action |
|---|---|
| Truncation fails / database error | Stop immediately; do not retry blindly; if vpxd starts, bring services up and reassess; otherwise restore the most recent validated file-based backup into a new appliance (A5.8) |
| Space did not free after truncation | `VACUUM FULL` on the specific table (L3, maintenance window) or expand the disk (A3.6 step 7) |
| Services will not restart after database work | Escalate to Broadcom with the support bundle; a restore is usually faster than diagnosis |

### A3.9 Prevention

1. **Alert on capacity, not just failure:** `/storage/seat` — 70% warning, 80% high, 90% critical; `/storage/log`, `/storage/db`, `/storage/core` — 80% warning. Alert on **growth rate** (> 500 MB/day on a stable inventory) as the leading indicator.
2. **Keep the reserved headroom file** on SEAT, and document it so nobody "tidies it away".
3. **Statistics-level discipline** — document the chosen level per vCenter and review after large inventory growth.
4. **Retention discipline** — define and record event/task retention; review annually.
5. **Storm detection** — alarm on abnormal event rates; fix hardware-sensor alarm storms at the source (host patches/firmware).
6. **Monitor autovacuum health** (dead-tuple % on `vpx_*` tables) in the monthly database review.
7. **Quarterly capacity review** — correlate SEAT growth with inventory and retention; resize in a planned window, never during an outage.
8. **Do not store backups or support bundles on the appliance** long-term; move them to the backup target.

### A3.10 Anti-patterns

* `rm` on anything under `/storage/seat`, `/storage/db`, `/storage/log` (data loss / corrupted database).
* Stopping vPostgres abruptly (`kill -9`) to "release" space.
* Truncating anything other than the event/task class (destroys integrity and history).
* Deleting performance-statistics tables without approval — capacity planning loses its history.
* Restoring a long retention window *after* a cleanup, undoing the fix.
* Letting usage climb back into the danger zone without fixing the storm source.

### A3.11 References

* Broadcom KB **318931** — `/storage/seat` disk 100% full on VCSA 6.x/7.x/8.x (log signatures, largest-table queries, truncation procedure, verification).
* Broadcom KB **390417** — `/storage/seat` disk exhaustion alert on vCenter (identify the filler; purge options incl. the `_reset_event_sequence` script; disk-expansion workaround).
* Broadcom KB **2110031** — Delete old tasks, events and statistics data in vCenter Server (supported purge scripts).
* Broadcom KB — *vCenter Server services fail to start due to high /storage/seat* (search by title).
* Broadcom KB — *Increasing the disk space for the vCenter Server Appliance in vSphere 6.5, 6.7, 7.0 and 8.0*.
* Broadcom KB — VCDB defragmentation / `VACUUM FULL` guidance.

---

## A4. vCenter High Availability (VCHA) — Degraded Cluster, Failed Failover, Isolated Node

| Attribute | Detail |
|---|---|
| SOP ID | **A4** |
| Default severity | **S1** if the Active node is isolated and no failover occurs; **S3** if the cluster is degraded but serving |
| Frequency | Common in VCHA deployments |
| Typical MTTR | 30 min (successful failover) – 4 h (destroy/rebuild) |
| Downtime | Possible management outage during failover or rebuild; workloads unaffected |
| Skills | L3 executes; L2 supports |
| Change required | Yes (Emergency change if the Active node is isolated) |

### A4.1 Architecture reminder (this drives every diagnostic)

VCHA is a **3-node** cluster:

| Node | Role |
|---|---|
| **Active** | Serves all vCenter requests; owns the management IP/FQDN |
| **Passive** | Continuous replica; ready to take the Active role |
| **Witness** | Quorum/arbitration only; holds no VM data |

| Network | Purpose | Typical properties |
|---|---|---|
| **Management network** | Client traffic, node identity, failover orchestration | Same subnet/VLAN as the Active node; must reach vCenter clients |
| **HA (heartbeat) network** | Node-to-node state replication and heartbeats | Dedicated VLAN/port group; **latency < 10 ms RTT**; MTU consistent end to end |

Requirements whose violation causes most VCHA incidents: separate ESXi hosts (DRS anti-affinity), separate datastores, dedicated HA network, all three nodes licensed, and **no snapshots or backups of the Passive/Witness nodes**.

### A4.2 Trigger and symptoms

* Alarm: `vCenter HA cluster state is currently degraded` / `isolated` / `destroyed`.
* The Active node reports all services down and states it is **isolated** (isolation mode protects against split-brain).
* The Passive node did not become Active after a failure (no failover, or failover stalled).
* Witness node missing or unreachable; the VCHA view shows a broken node.
* Deployment/configuration failures during (re)build:
  * `A general system error occurred: Failed to ssh connect peer node ...` — typically HA-network misconfiguration (VLAN not allowed on trunks, wrong port group on the heartbeat vNIC).
  * Basic-mode configuration stuck at ~33% / 96% with `The session is not authenticated. You do not hold privileges ...` plus clone failures — documented on **NFSv3** datastores (40-second NFSv3 lock timeout vs. automatic clone).
* `/var/log/vmware/vcha/` on the nodes contains the detail.

### A4.3 Impact

* **Degraded:** VCHA protection is not functional but vCenter serves requests — treat as **S3 with a short deadline**; never leave it degraded for weeks.
* **Isolated Active node:** total management outage (no UI/API) while VMs keep running.
* **Active + Witness lost, Passive healthy:** management is down until the Passive is forced to standalone (A4.9).

### A4.4 Root causes (ranked)

1. **HA network problems** — wrong port group on the heartbeat vNIC, VLAN not allowed on the ESXi uplink trunk, MTU mismatch, routing/firewall blocking, latency > 10 ms.
2. **Snapshot-based backups of the Passive/Witness nodes** — break replication and produce a permanently degraded state.
3. **Placement violations** — Active/Passive/Witness sharing a host or datastore, missing anti-affinity, or DRS acting against the design.
4. **Witness node failure** (storage, host, deletion) — quorum loss prevents clean failover.
5. **Resource starvation / storage latency** on the Passive node's host — replication falls behind.
6. **NFSv3 datastores** backing the vCenter nodes during VCHA deployment (clone lock timeout).
7. **Appliance changes applied to individual VCHA nodes** (re-IP, certificate reset on one node only, manual file edits).
8. **Unsupported/older vCenter build** with known VCHA defects.

### A4.5 Evidence collection

```bash
# On each VCHA node (console or SSH; some commands are limited in isolation mode)
service-control --status --all
cat /etc/vmware-vcha/vcha.conf 2>/dev/null      # node role/config view (path and format vary by build)
tail -300 /var/log/vmware/vcha/*.log
tail -100 /var/log/vmware/vpxd/vpxd.log
ip -br a; ip r                                  # confirm management and HA IPs
```
```bash
# Network validation, from each node to each peer HA IP
ping -c 5 <peer_ha_ip>
ping -c 20 -i 0.2 <peer_ha_ip> | tail -3        # confirm RTT < 10 ms
# MTU consistency end to end (use your build's supported tool; test with large payloads)
```
From the vSphere Client / ESXi:
* VCHA view: placement (host, datastore) of Active, Passive and Witness.
* Each node VM: vNIC list, **port group of the heartbeat vNIC**, host, datastore, anti-affinity rules.
* ESXi host logs for the failure window (`/var/log/vmkernel.log`, `/var/log/hostd.log`) and the vSwitch/port-group configuration for the HA VLAN.
* Backup platform: is anything snapshotting the Passive or Witness node?

### A4.6 Decision tree — recovering service

```
Is the vCenter management UI/API available?
|
+-- YES (degraded VCHA, vCenter serving)
|      --> A4.7 Repair in place
|
+-- NO (Active isolated, or Active + Witness lost)
       |
       +-- Did the Passive node come up as Active?  -> wait; if stalled > 15 min continue
       |
       +-- Active node recoverable (host/storage/network fixed)?
       |      --> Bring the Active node back; it may reclaim the Active role automatically
       |
       +-- Witness only recoverable?
       |      --> A4.8 Recover with the Witness (reset primary role on the Passive, reboot)
       |
       +-- Active + Witness not recoverable?
              --> A4.9 Force the Passive node to standalone, then rebuild
```

### A4.7 Repair in place (degraded but serving)

1. **Fix the network first.** Verify that the heartbeat vNIC on all three nodes is on the intended port group, the VLAN is trunked on every host uplink it traverses, MTU is identical end to end, and RTT between all pairs is < 10 ms. VCHA cannot self-heal over a broken heartbeat network.
2. **Stop backups of the Passive/Witness nodes.** Redesign the job so only the Active node is protected (file-based backup is the supported mechanism), through change control.
3. **Verify placement:** three hosts, three datastores, anti-affinity present, DRS not fighting it. Correct violations with vMotion — never with snapshots.
4. **Restore a missing Witness** by redeploying it through the VCHA workflow (vSphere Client → vCenter → Configure → vCenter HA → Witness deployment), supplying the HA-network details.
5. **Confirm convergence:** the VCHA view returns to *Healthy*. If a node remains out of sync although the network is proven good, continue to A4.8/A4.9.
6. **Test failover** (`Initiate Failover` in the VCHA workflow) during a maintenance window once healthy — an untested VCHA cluster is a false sense of security.

### A4.8 Recover with the Witness (documented failover-failure path)

Broadcom TechDocs *Resolving Failover Failures* defines this branch:

1. If the **Active node recovers** from the failure, it becomes Active again — verify and stop here.
2. If the **Witness node recovers**, log in to the **Passive** node through the VM console, enable the Bash shell (`shell` at the appliance shell prompt), run the documented **reset-primary** command (`vcha-reset-primary`), then reboot the Passive node.
3. Confirm which node is Active: check the VCHA state in the vSphere Client, or run `service-control --status --all` on each node (only the Active node runs the full service set).

> **Command-name discipline.** VCHA CLI verbs have changed across releases (`destroy-vcha -f` in the 6.5/6.7 era; `vcha-destroy` / `vcha-reset-primary` in later TechDocs). Before running anything, enumerate the available tools on the node (`ls /usr/lib/vmware-vcha/`, or tab-complete `vcha-`) and read `<command> --help`. Never type a VCHA command from memory in production.

### A4.9 Force the Passive node to standalone (Active and Witness unrecoverable)

Use only when the Active and Witness nodes cannot be recovered and business continuity requires vCenter management.

1. **Confirm the decision** with L3 and management. This destroys the HA cluster configuration (VM data is unaffected — the Passive node is a full replica of the vCenter state as of the last synchronization).
2. Log in to the **Passive** node console (its UI is down while in standby/isolation) and enable the shell (`shell`).
3. **Delete (or power off and isolate) the Active and Witness node VMs** so they cannot return to the network with the same IP/FQDN and cause a conflict.
4. On the Passive node, run the documented **destroy/standalone** command (`vcha-destroy` in current TechDocs; `destroy-vcha -f` on older builds) and reboot.
5. The node then boots as a **standalone vCenter Server** with the last replicated state. Verify:
   * Services and certificates: `service-control --status --all` plus the A1.4 certificate inventory.
   * DNS/IP identity: the surviving node keeps the original management IP/FQDN by design — confirm both forward and reverse resolution.
   * ESXi hosts reconnect (rescan/reconnect manually if any remain disconnected).
   * Take a fresh **file-based backup** (A5) and confirm the backup job definition still targets the right destination.
6. Rebuild VCHA from scratch in a maintenance window **after** the root cause is fixed (network, storage, placement, or backup-job design).

### A4.10 Verification of recovery

| # | Check | Pass criterion |
|---|---|---|
| V1 | VCHA cluster state | *Healthy* (not degraded/isolated) |
| V2 | Node roles | Exactly one Active; Passive in sync; Witness present |
| V3 | Heartbeat network | RTT < 10 ms between all node pairs, MTU consistent, no packet loss |
| V4 | Placement | Three distinct hosts, three distinct datastores, anti-affinity respected |
| V5 | vCenter service | All services `Running` on the Active node; UI/API functional |
| V6 | Failover test | Planned failover completes within the documented RTO, then fail back |
| V7 | Backup design | Only the Active node is protected by backups/snapshots; job verified |
| V8 | Alarm routing | The VCHA state alarm reaches the on-call queue (prove it with a test) |

### A4.11 Rollback

| Situation | Action |
|---|---|
| Repair in place made things worse | Revert to the last known-good state: restore the Active node from the most recent validated **file-based backup** (A5) or promote the Passive node (A4.9) |
| Forced standalone rolled back recent vCenter changes | Re-apply the changes recorded in the change log — the standalone node carries only the state as of last replication |
| Failover test failed | Do not leave the cluster in a test state; re-establish the original roles, then debug with L3/Broadcom before the next change window |

### A4.12 Prevention

1. **Dedicate the HA network:** separate VLAN, trunked on every relevant host uplink, verified MTU, latency monitored (< 10 ms), documented in the network CMDB.
2. **Never snapshot or back up Passive/Witness nodes** — encode this in the backup platform and in §5.4.
3. **Enforce anti-affinity** for VCHA nodes (separate hosts and datastores); alert if a node lands on a shared host/datastore.
4. **Monitor the Witness node** with the same alerting rigour as the Active node.
5. **NFSv3 caveat:** if the vCenter nodes sit on NFSv3 datastores, use the documented deployment workarounds (perform clone operations on the same ESXi host with `config.vpxd.vcha.drsAntiAffinity` temporarily set to `False`, or use the manual clone method) and revert the advanced setting afterwards.
6. **Annual failover test** in a maintenance window, with the RTO result recorded.
7. **Resource headroom** on the Passive node's host — replication must not compete with saturated storage or CPU.
8. **Change control on VCHA nodes:** no per-node certificate resets, re-IPs, or manual edits outside a reviewed procedure.

### A4.13 References

* Broadcom TechDocs — *vSphere Availability → vCenter Server High Availability → Troubleshoot Your vCenter HA Environment → Resolving Failover Failures* (7.0 and 8.0 editions) — authoritative command set (`vcha-reset-primary`, `vcha-destroy`) and the witness/passive recovery branches.
* Broadcom KB (legacy ID **50121880**) — *vCenter HA Basic Mode fails during Passive/Witness cloning when using NFSv3 datastore* (stuck at 33%/96%, NFSv3 lock timeout, workarounds).
* Broadcom TechDocs — *vCenter HA requirements* (latency, placement, licensing, networking).
* Broadcom KB — VCHA degraded-state articles (search "vCenter HA cluster state is currently degraded").

---

## A5. vCenter File-Based Backup Fails / Restore Not Proven (VAMI Backup & Restore)

| Attribute | Detail |
|---|---|
| SOP ID | **A5** |
| Default severity | **S2** (loss of recoverability is an S2 even when vCenter is healthy; higher if a restore fails when needed) |
| Frequency | Common — failures are often silent |
| Typical MTTR | 30 min – 2 h per failure cause |
| Downtime | None for backup fixes; a restore requires an outage |
| Skills | L2 executes; the Backup Admin owns the destination |
| Change required | Yes for restore tests; a failed-backup fix is still logged as an activity |

### A5.1 Trigger and symptoms

| Symptom (VAMI UI / `/var/log/vmware/applmgmt/backup.log`) | Root-cause class |
|---|---|
| `BackupManager encountered an exception. Exception: Full backup not allowed during VM snapshot` | Stale `backupMarker.txt` snapshot marker |
| `Error during component vum backup`, `BrokenPipeError: [Errno 32] Broken pipe`, `curl: (79) Error in the SSH layer` | Damaged VUM/component backup state from an interrupted job |
| `tar: Cannot write: Broken pipe`, `No space left on device` | Destination full, or per-user quota / inodes exhausted |
| Scheduled backups fail while manual backups to the same target succeed | `backup-metadata.json` mismatch on the destination |
| Restore fails, or jobs complete but the artifacts were never tested | No restore-validation process |

### A5.2 Impact

* No recoverable point-in-time copy of vCenter configuration (inventory, permissions, alarms, distributed switch definitions, tags, certificates).
* A vCenter rebuild becomes a multi-day manual exercise — this is the real business impact even though "nothing is down".
* A failed restore during an outage extends the outage from hours to days.

### A5.3 Root causes (ranked)

1. **Stale `backupMarker.txt`** in `/etc/vmware` — left by an interrupted backup, a migration/clone, or third-party backup software that snapshotted the appliance without cleanup.
2. **Destination capacity/quota/inode exhaustion** — roughly **2× the vCenter used space** must be free.
3. **Interrupted prior backup** leaving inconsistent VUM/component state.
4. **Destination metadata mismatch** (`backup-metadata.json`) — affects scheduled jobs only.
5. **Target drift** — path, protocol (SFTP vs SCP), permissions, key algorithms, expired service account, firewall/DNS change.
6. **No restore-test process** — failures stay hidden until the day they matter.
7. **Backups taken concurrently with snapshots/vMotion**, or with the SEAT component included, causing timeouts and oversized transfers.

### A5.4 Evidence collection

```bash
# 1. Stale snapshot marker?
ls -l /etc/vmware/backupMarker.txt

# 2. Authoritative backup log
tail -300 /var/log/vmware/applmgmt/backup.log
grep -iE "error|exception|failed|broken pipe|no space" /var/log/vmware/applmgmt/backup.log | tail -40

# 3. Appliance space and health
df -h; df -i
service-control --status --all

# 4. Backup history/schedule artefacts
ls -l /storage/applmgmt/backup_restore/ 2>/dev/null
cat /storage/applmgmt/backup_restore/backup_schedule.json 2>/dev/null

# 5. Time (authentication and TLS to the destination depend on it)
timedatectl status
```
On the **destination** (Backup Admin):
```bash
df -h <backup_path>; df -i <backup_path>
ls -lh <backup_path>                    # backup folders, sizes, timestamps
ls -l  <backup_path>/backup-metadata.json
# also confirm the SFTP/SCP account's storage quota
```
From VAMI (5480): **Backup** → job status, schedule, and last-run detail; VAMI → **Monitor** for appliance disk usage.

### A5.5 Resolution procedure

**Step 1 — Clear a stale snapshot marker (only after confirming nothing is genuinely running).**
```bash
# Confirm the appliance has no snapshots (vSphere Client) and no backup job is running, then:
ls -l /etc/vmware/backupMarker.txt
rm -f /etc/vmware/backupMarker.txt
```
Retry the backup from VAMI.

**Step 2 — Fix destination space/quota/inodes (usual cause of "Broken pipe / No space left").**
* Confirm ≥ **2×** the appliance's used space is free on the target, the backup account has no restrictive quota, and inodes are available (`df -i`).
* Free space by reducing **retention** or deleting the **oldest** sets — never the newest.
* Re-run and confirm completion.

**Step 3 — Repair corrupted VUM/component backup state.**
When the log shows `Error during component vum backup` / `BrokenPipeError` with the SSH-layer error:
1. Take a short-term snapshot of the vCenter VM (§5.4).
2. Reset the **VUM (Update Manager) database** using the Broadcom KB procedure for your version.
3. Move the local history/schedule artefacts aside so the scheduler rebuilds them:
   ```bash
   mv /storage/applmgmt/backup_restore/backup-history.json  /storage/core/
   mv /storage/applmgmt/backup_restore/backup_schedule.json /storage/core/
   ```
4. Restart the appliance management service:
   ```bash
   service-control --stop applmgmt && service-control --start applmgmt
   ```
5. Recreate the schedule in VAMI and run the backup.

**Step 4 — Fix scheduled-only failures (metadata mismatch).**
On the destination, rename the metadata index so the scheduler recreates it:
```bash
mv <backup_path>/backup-metadata.json <backup_path>/backup-metadata.json.old
```
Then re-run the **scheduled** job and confirm success.

**Step 5 — Re-validate the target configuration.**
* Path exists and is writable by the backup account; correct protocol for your destination; credentials valid; no firewall/NAT change between appliance and target.
* Confirm retention, encryption, and passphrase settings match the documented standard, and that the passphrase is stored in the privileged vault.

**Step 6 — Prove the backup is usable (mandatory; this is the real deliverable).**
Perform a **test restore** at least annually and after any major vCenter version change:
1. Deploy a new appliance from the vCenter ISO in the same version/build (or later patch), using the same FQDN/IP **inside an isolated network** or lab.
2. Choose **Restore** during installer Stage 1/2 and supply the backup location and passphrase.
3. Confirm the restored appliance starts, services come up, and inventory, permissions, tags, and distributed switches are present.
4. Record date, source backup, duration, result, and issues found, and file it with the backup records.

### A5.6 Verification of recovery

| # | Check | Pass criterion |
|---|---|---|
| V1 | Manual backup | Completes with no exceptions in `backup.log` |
| V2 | Scheduled backup | The next scheduled run completes without intervention |
| V3 | Artefacts | New backup folder on the destination with expected contents/size and a fresh `backup-metadata.json` |
| V4 | Marker | `/etc/vmware/backupMarker.txt` **absent** after the job |
| V5 | Retention | Retained sets match policy; destination stays < 80% full |
| V6 | Restore test | A documented successful test restore within the last 12 months, with the record attached |
| V7 | Alerts | Monitoring alerts on backup **failure**, not only on completion |

### A5.7 Rollback

| Situation | Action |
|---|---|
| Fix introduced risk (e.g. VUM reset while updates were staged) | Restore the pre-change snapshot; re-stage update baselines; re-verify VUM compliance |
| `applmgmt` will not start after moving history files | Move the JSON files back from `/storage/core/`, restart `applmgmt`, then escalate with `backup.log` evidence |
| Test restore damaged the lab | Rebuild the lab appliance — no production impact; isolation is the point |

### A5.8 Restoring the appliance (when it is actually needed)

1. Request a maintenance window and confirm the source vCenter will be offline (the same FQDN/IP cannot exist twice on the network).
2. **Record the current version/build** — a file-based backup must be restored with the **same version/build or a later patch**; older-build restores are unsupported.
3. Power off the source appliance but **do not delete it yet** — keep it as a fallback and for log forensics.
4. Deploy the replacement appliance through the installer's **Restore** path, pointing to the backup location, and supply the passphrase.
5. Expect to: re-verify certificates (A1), confirm the deployment size/node count matches the source, verify DNS/IP identity, confirm services, and reconnect/rescan ESXi hosts.
6. Verify using A2.7 and A5.6, then run a **fresh backup** immediately.
7. Record the restore as a change with start/end times and outcomes.

### A5.9 Prevention

1. **Alert on failures, not silence** — monitoring rule on `backup.log` errors / VAMI job status so a failed backup becomes an incident within 24 h.
2. **Destination buffer** — ≥ 2× used space free, alerts at 70%/85%, backup account with generous/no quota.
3. **Clean snapshot discipline on the appliance** (§5.4): never leave a snapshot; never let third-party tools snapshot the VCSA without cleanup; check for a leftover `backupMarker.txt` after any clone/migration activity.
4. **Two copies, one offsite** — file-based backup to a hardened target plus an exported copy to secondary/offsite storage.
5. **Exclude SEAT from frequent backups** where policy allows (it is large and changes constantly); if required, schedule it in a longer window.
6. **Document and test the restore runbook annually**, including passphrase retrieval and the isolated-network approach.
7. **Keep the matching vCenter ISO/build** on hand for same-build restores.
8. **Verify backups after every vCenter upgrade/patch** — schema changes are the classic trigger for silent failures.

### A5.10 Anti-patterns

* Treating a VM snapshot as a backup (unsupported as a recovery method; also a frequent cause of A4 and B2 states).
* Deleting the newest backup set to make room.
* Restoring onto the network while the original appliance still owns the FQDN/IP.
* Never testing a restore — then discovering the passphrase is lost during an outage.
* Backing up Passive/Witness VCHA nodes.
* Ignoring "completed with warnings" messages in VAMI.

### A5.11 References

* Broadcom KB **344841** — File-based backup in VAMI fails with *"Full backup not allowed during VM snapshot"* (zero-byte `backupMarker.txt` in `/etc/vmware`; causes include interrupted backups, vMotion, and third-party snapshot tools).
* Broadcom KB **441880** — Troubleshooting VCSA file-based backup failures caused by **stale configuration files** during migration/re-IP (local marker; remote `backup-metadata.json` rename fix).
* Broadcom KB **430761** — VCSA file-based backup fails with *"Broken pipe"* and *"No space left on device"* (destination capacity, quota and inode checks; ≥ 2× used space guidance).
* Broadcom KB **380876** — VAMI file-based backup fails with *"Error during component vum backup"* (VUM database reset, move `backup-history.json`/`backup_schedule.json` to `/storage/core/`, restart `applmgmt`).
* Broadcom TechDocs — *Backing up and restoring the vCenter Server Appliance* (file-based backup/restore; supported version/build rules).
* Broadcom KB — *Best practices for vCenter Server Appliance backup and restore* (search by title).

---
---

# PART B — Virtual Machine Issues Managed Through vCenter

---

## B1. VM Cannot Power On — "Failed to Lock the File" / "Unable to Access File Since It Is Locked"

| Attribute | Detail |
|---|---|
| SOP ID | **B1** |
| Default severity | **S2** (S1 if the VM is business-critical or a whole datastore is affected) |
| Frequency | Common — usually follows a host crash, storage event, or failed backup |
| Typical MTTR | 20 min – 2 h (fast paths); 4 h – 2 days if datastore metadata repair is required |
| Downtime | The affected VM is already down; a host reboot (if needed) affects that host's VMs |
| Skills | L2 executes; L3 + Broadcom for VOMA/datastore metadata work |
| Change required | Emergency change to restore service; planned change for host reboot |

### B1.1 Trigger and symptoms

Power-on (or snapshot-delete, or consolidation) fails with one or more of:

* `Cannot open the disk '/vmfs/volumes/<datastore>/<VM>/<VM>-000001.vmdk' or one of the snapshot disks it depends on. Failed to lock the file.`
* `Unable to access file <path> since it is locked`
* `Virtual machine cannot be powered on: Lost previously held lock ...`
* The VM is `inaccessible` in the inventory, or the .vmx disappears from the folder view.
* On the host: `/var/run/log/vmkernel.log` shows an **active exclusive lock (type 10c00001)** on the VMDK.

Locks are normal on a running VM. The incident is an **unexpected** lock: one held by a crashed host, a stale registration, a backup proxy after a failed hot-add backup, or leftover metadata.

### B1.2 Impact

* Single VM outage (business impact depends on the workload). This is a common cause of "VM down, no obvious reason" bridge calls.
* If several VMs on one datastore fail together, suspect storage (APD/PDL) — resolve the storage incident first.
* Repeated power-on attempts add noise and create conflicting management tasks — **retry once, then investigate**.

### B1.3 Root causes (ranked)

1. **Host crash, PSOD, or hung management agents** leaving a stale exclusive lock.
2. **Backup appliance/proxy hot-add attachment** still present after a failed or aborted backup job.
3. **VM registered/running on another host** (duplicate registration after a crash or a botched migration).
4. **NFS datastore `lck-` files** left behind by an unclean shutdown/download host.
5. **VMFS metadata inconsistency or datastore corruption** (typically affects multiple VMs; see the STOP condition).
6. **Lost or degraded storage paths / APD** — the datastore is read-only or partially available.
7. **A device left attached** (CD-ROM ISO on a host-local path, USB, serial) — different error text, same workflow class (see also B3).

### B1.4 Evidence collection (never skip — this determines whether a reboot is safe)

```bash
# On the ESXi host where the VM is registered:

# 1. Exact error text and affected file: vSphere Client -> VM -> Monitor -> Tasks and Events,
#    plus the VM's own log on the datastore:
#    /vmfs/volumes/<ds>/<vm>/vmware.log   (look for the first failed open/lock, and its path)

# 2. Lock ownership for VMFS files
vmfsfilelockinfo -p /vmfs/volumes/<ds>/<vm>/<vm>.vmx
vmfsfilelockinfo -p /vmfs/volumes/<ds>/<vm>/<vm>-000001-delta.vmdk -v -u administrator@vsphere.local

# 3. Lock owner documented as a host MAC (VMFS)
vmkfstools -D /vmfs/volumes/<ds>/<vm>/<vm>-flat.vmdk

# 4. Which process/VM holds the file on the owning host
lsof | egrep 'Cartel|<vm>-000001-delta.vmdk'
esxcli vm process list                     # map Cartel/World ID to the VM

# 5. Is the VM running somewhere else (or twice)?
esxcli vm process list                     # run on every host in the cluster if needed
vim-cmd vmsvc/getallvms | grep -i <vm>

# 6. Datastore and path health
esxcli storage filesystem list
esxcli storage core path list | egrep -i '<naa|state>' | head -40
esxcli storage core device list -d naa.<id>

# 7. vmkernel evidence around the failure
grep -iE 'lock|APD|PDL|scsi|reserv' /var/run/log/vmkernel.log | tail -60
```

**Snapshot chain sanity check** (do this before declaring the file "just locked"): open the VM's settings and record the active backing for every disk; if the active backing is a delta, the chain must be intact:
```bash
vmkfstools -e /vmfs/volumes/<ds>/<vm>/<vm>-000002.vmdk   # chain consistency check (VM powered off)
grep -i '\.vmdk' /vmfs/volumes/<ds>/<vm>/<vm>.vmx         # read-only cross check of configured disks
```

### B1.5 Immediate containment

1. **Retry power-on exactly once** after clearing any stale task in vCenter — then stop retrying.
2. Take a **support bundle from the owning host** before rebooting anything: `vm-support -w /vmfs/volumes/<healthy_ds>`.
3. Contain the blast radius: do not delete or rename any VM files; do not "clean up" `*-00000N.vmdk` or `.lck` entries.
4. If several VMs on one datastore are affected simultaneously: **treat it as a storage incident** — check APD/PDL state and escalate to L3 before touching individual VMs.

### B1.6 Resolution procedure

**Step 1 — Determine whether the VM is genuinely running elsewhere.**
If `esxcli vm process list` on any host shows the VM's Cartel/World, the VM **is** running: fix the *management* view (refresh/re-register) rather than fighting the lock. Forcing a power-off is a business decision (data loss risk) — get approval.

**Step 2 — Detect and release a backup-proxy / third-party attachment.**
* Open **Edit Settings** on every backup proxy / helper VM and compare each hard disk's full datastore path with the locked file in the error.
* Confirm in the backup console that no job is running or retrying.
* If an attachment is stranded: **Remove from virtual machine** — **never** choose *Delete files from datastore* for the target VM's disk.

**Step 3 — Release the lock on the owning ESXi host (host healthy).**
```bash
# On the host that owns the lock
services.sh restart                     # restart hostd/vpxa management agents (non-disruptive to running VMs)
```
Then retry power-on. If the lock persists and the owning host is otherwise healthy, continue to Step 4.

**Step 4 — Reboot the lock-holding host (standard remedy).**
1. Place the host in maintenance mode (DRS evacuates workloads) — or accept the outage window for the host's VMs if DRS is unavailable.
2. Reboot the host (`reboot` from ESXi Shell, or DCUI → *Reboot*).
3. After the host returns, exit maintenance mode and retry power-on.
4. Verify (B1.7). If power-on now succeeds but the datastore showed any inconsistency symptoms, still complete Step 5 checks.

**Step 5 — NFS only: remove stale `lck-` files.**
1. Confirm the VM is **powered off** everywhere (check every host).
2. Create a backup directory in the VM folder and move the lock artifacts aside (do not delete):
   ```bash
   cd /vmfs/volumes/<nfs_ds>/<vm>
   mkdir -p lck_backup
   mv lck-*  .lck*  lck_backup/ 2>/dev/null
   ls -lah lck_backup
   ```
3. Retry power-on.

**Step 6 — STORAGE/DATASTORE CONSISTENCY — STOP CONDITION.**
If any of the following are true, **stop and escalate to L3 + Broadcom**:
* Multiple VMs affected on the same datastore.
* `vmfsfilelockinfo`/`vmkfstools -D` returns an owner that cannot be reconciled with a real host, or vmkernel shows type `10c00001` exclusive locks persisting.
* The snapshot chain is inconsistent (missing parent, CID mismatch, an extent that will not open).
* VOMA would be required.

The documented L3 path is: record affected VMs, confirm backups exist, **Storage vMotion running VMs off** the datastore, unmount it from all hosts, then run VOMA **dump** and **check** (`voma -m vmfs -f dump -d /vmfs/devices/disks/naa.<id>:1 -D <path>/VOMA_OUT/` then `voma -m vmfs -f check -a -d ... -s ...`), then mount and re-register. **`voma ... advfix` is Broadcom-supported only** — it can delete files, and any file it damages must be restored from backup. Never run it without a validated restore point and Broadcom engagement.

### B1.7 Verification of recovery

| # | Check | Pass criterion |
|---|---|---|
| V1 | Power-on | VM powers on and reaches the guest OS |
| V2 | `vmware.log` | No lock/open failures in the last power-on cycle |
| V3 | Lock state | `vmfsfilelockinfo -p <vmx>` shows the expected owner (running VM = its own host) — no stale foreign owner |
| V4 | Datastore health | `esxcli storage filesystem list` shows the volume mounted and not read-only; path states all `Active` |
| V5 | `vmfsfilelockinfo`/`vmkfstools -D` | No unexplained lock owner remains |
| V6 | Backup | The next backup of that VM completes (proves the proxy attachment is truly gone) |
| V7 | Snapshot state | No `Consolidation needed` warning (cross-check **B2**) |

### B1.8 Rollback

| Situation | Action |
|---|---|
| Host reboot did not clear the lock | Stop; do **not** force-remove locks or edit VMFS metadata; escalate to L3/Broadcom with the bundle and evidence |
| Waiting for the owning host to drain is unacceptable to the business | Escalate with the impact analysis: the alternative (forced lock release / metadata work) risks **data loss** — this must be a documented business decision, not an admin convenience |
| VM powers on but data looks wrong | Immediately power off, preserve the datastore as-is, and restore from backup — do not consolidate or snapshot first |

### B1.9 Prevention

1. **Eliminate the trigger class:** fix host crashes (firmware/driver/patches), monitor for host disconnects and APD/PDL events, and keep management agents healthy.
2. **Backup hygiene:** require the backup product to detach hot-added disks and clean up after failed jobs; alert on "backup job failed" so stranded attachments do not persist for days.
3. **No duplicate registrations:** ensure DRS/HA and host naming are stable; after a host crash, verify VM inventory state before re-registering.
4. **NFS cleanliness:** monitor for leftover `lck-` files after unclean NFS host events; document the safe removal procedure (B1 Step 5).
5. **Capacity and health:** alert on datastore free space and path state; keep VMs' snapshot chains short to reduce the surface area.
6. **Practice the investigation, not the panic:** run `vmfsfilelockinfo` in a lab so responders are comfortable *before* a real event.

### B1.10 Anti-patterns

* Rebooting every host in the cluster to "find the lock".
* Force-releasing locks (`vmkfstools`/`esxcli` undocumented flags or CLI on the filer) while a VM may still be running → guaranteed data loss.
* Deleting `.lck`, `-flat.vmdk`, `-delta.vmdk`, or `.ctk` files to "clean up".
* Running `voma ... advfix` without Broadcom and without a validated backup.
* Attaching the base disk to bypass a broken chain — this silently discards every write in the missing delta.

### B1.11 References

* Broadcom KB **10051** — *Investigating Virtual Machine file locks on ESXi Host(s)* (lock types, `vmfsfilelockinfo`, `lsof | egrep 'Cartel|...'`, `esxcli vm process list`, host reboot and NFS `.lck` procedures).
* Broadcom KB (article **392268**) — *Virtual machine is inaccessible or cannot be powered on due to a file lock* (identify owner, confirm no backup/snapshot running, avoid forced removal).
* Broadcom KB (article **393999**) — *Virtual Machine cannot be powered on: "Lost previously held lock"* (stale locks, VOMA dump/check procedure, advfix caveats, restore-from-backup outcome).
* Broadcom KB — *Validating the .vmx settings of a virtual machine*.
* Broadcom KB — *Overview of migration compatibility error messages* (for the device-attachment variants of this error).
* Broadcom KB — *vSphere On-disk Metadata Analyzer (VOMA)* usage and disclaimers.

---

## B2. "Virtual machine disks consolidation is needed" — Snapshot Consolidation Fails

| Attribute | Detail |
|---|---|
| SOP ID | **B2** |
| Default severity | **S3** (S2 if backups are failing or the VM is write-intensive with a growing delta) |
| Frequency | Very common — the most frequent snapshot-related issue in most estates |
| Typical MTTR | 15 min – 4 h (longer for multi-TB VMs; consolidation is I/O intensive) |
| Downtime | Usually none (online consolidation); some paths require a VM power-off |
| Skills | L2 executes; L3 if the chain is inconsistent |
| Change required | No for the standard Consolidate action; yes if the VM must be powered off or cloned |

### B2.1 Trigger and symptoms

* VM **Summary** shows: `Virtual machine disks consolidation is needed` (warning icon).
* Snapshot Manager shows **no snapshots**, yet the datastore folder still contains delta/redo files (`<vm>-000001.vmdk`, `-000002.vmdk`, …) and grows over time.
* Consolidate/Delete-All tasks fail with: `An error occurred while consolidating disks: Failed to lock the file`, `Unable to access file since it is locked`, or `Consolidation failed for disk node`.
* Backup jobs fail or warning: some backup products refuse to protect a VM in this state.
* Datastore free space trending down quickly on an otherwise stable VM.

**Meaning:** vCenter's snapshot inventory and the actual on-disk state disagree. It does **not** mean the delta files are junk — the newest writes may live only there.

### B2.2 Impact

* Backups may fail (unprotected data) and VM write performance degrades as the delta chain grows.
* Datastore capacity risk: an unmanaged delta can fill a datastore, which becomes a multi-VM outage.
* A growing chain increases the risk of an unrecoverable chain break (RPO loss).

### B2.3 Root causes (ranked)

1. **Snapshot delete/consolidate did not complete** (task aborted, timeout, interruption during a backup window).
2. **Backup proxy still holds the disk** (hot-add attachment left behind after a failed backup) — blocks consolidation exactly as it blocks power-on (B1).
3. **Insufficient free space** on the datastore holding the chain (Broadcom's insufficient-space guidance for the file-too-large scenario is ≈ **1.5× the total snapshot-file size** free; thin base disks and online deltas can grow during the commit).
4. **More than 32 snapshots** on the VM (Broadcom-recommended maximum) or a very long chain.
5. **Host management agents/crashed host** holding the lock; APD during consolidation.
6. **Change Block Tracking (CBT/CTK) inconsistency** (`-ctk.vmdk` files) breaking the chain reconciliation.
7. **Chain corruption** — missing parent, CID mismatch, "The parent virtual disk has been modified since the child was created" (KB 1007969 class).

### B2.4 Evidence collection

```bash
# On the ESXi host (or via datastore browser for the folder listing)

# 1. Chain inventory: list every disk file and its size/timestamp
ls -lh /vmfs/volumes/<ds>/<vm>/            # look for -000001..-00000N.vmdk / -delta.vmdk / -ctk.vmdk

# 2. Which disk is active?
grep -i '\.vmdk' /vmfs/volumes/<ds>/<vm>/<vm>.vmx

# 3. Chain trace (inspect only; do not modify)
vmkfstools -q -v 10 /vmfs/volumes/<ds>/<vm>/<vm>.vmdk

# 4. Consistency check (VM powered off recommended)
vmkfstools -e /vmfs/volumes/<ds>/<vm>/<vm>-000002.vmdk

# 5. Free space on EVERY datastore holding any part of the chain
df -h /vmfs/volumes/<ds>

# 6. Lock holder (see B1 for the full method)
vmfsfilelockinfo -p /vmfs/volumes/<ds>/<vm>/<vm>-000001-delta.vmdk -v
lsof | egrep 'Cartel|<vm>-000001'
```
At scale (inventory-wide detection):
```powershell
# PowerCLI: find every VM needing consolidation
Get-VM | Where-Object {$_.ExtensionData.Runtime.ConsolidationNeeded} | Select-Object Name,PowerState

# Inventory-wide snapshot hygiene report (age and size)
Get-VM | Get-Snapshot | Where-Object {$_.Created -lt (Get-Date).AddDays(-3)} |
  Select-Object VM,Name,Created,@{n='SizeGB';e={[math]::Round($_.SizeGB,2)}} | Sort-Object Created
```

### B2.5 Immediate containment

1. **Freeze the growth driver:** confirm no backup job is currently running against the VM and stop any snapshot-creating automation.
2. **Protect capacity:** if the datastore is above 80% used, plan immediate space (migrate other VMs off with Storage vMotion or delete unrelated orphaned data — never touch this VM's chain).
3. **Do not delete delta files** and do not attempt manual merges — the supported paths are Consolidate, snapshot delete, or clone.
4. If the VM is critical, take an **application-consistent backup from inside the guest** as an extra fallback while you work.

### B2.6 Resolution procedure

**Step 1 — Run the standard consolidation (safest first).**
vSphere Client → right-click the VM → **Snapshots → Consolidate**. Confirm the prompt and watch **Recent Tasks** and datastore latency until `Consolidate virtual machine disk files` completes.
*Expected duration:* minutes to hours depending on delta size and storage speed. Warn the application owner about a potential I/O impact during the merge.

**Step 2 — If the task fails with a lock error, clear the lock first (B1), then retry.**
* Check backup proxies for stranded hot-added disks (B1 Step 2).
* Restart the management agents on the host holding the VM (`services.sh restart`) and retry consolidation.

**Step 3 — If Snapshot Manager shows no snapshots but deltas persist, use the new-snapshot technique.**
1. Take a **new** snapshot (name it, e.g. `consolidation-fix`, **no memory**, quiescing off if VSS/quiescing is failing).
2. Wait for it to complete.
3. **Delete All** snapshots (this commits everything, including the hidden deltas).
4. Confirm the warning clears. If it does not, continue.

**Step 4 — Perform the consolidation with the VM powered off.**
Power off the VM in an approved window, then run Consolidate (or *Delete All* if snapshots are listed). Offline consolidation avoids nearly all lock contention and is the most reliable single step for stubborn VMs.

**Step 5 — Move the VM to break host/datastore-specific locks.**
* vMotion to another host (clears host-specific hangs).
* Storage vMotion to another datastore (re-creates the files cleanly and resolves some inconsistency cases); this requires capacity and can be slow for large deltas.

**Step 6 — Re-register the VM.**
Remove the VM from the inventory (**do not delete from disk**), browse the datastore, and re-register the `.vmx`. Retry consolidation.
If you are asked "I moved it or copied it" on power-on, choose **I moved it** only if you truly moved it (that preserves CBT/UUID semantics); choosing wrongly can invalidate CBT.

**Step 7 — Clear a CBT/CTK inconsistency (documented workaround).**
Back up first, then disable CBT for the VM and re-enable it via a snapshot cycle:
```powershell
$vm = Get-VM -Name "<vm>"
$view = $vm | Get-View
$spec = New-Object VMware.Vim.VirtualMachineConfigSpec
$spec.changeTrackingEnabled = $false
$view.ReconfigVM($spec)
New-Snapshot -VM $vm -Name "Disable CBT" | Remove-Snapshot -Confirm:$false
```
Then retry consolidation. Treat CTK file deletion as a **last resort** documented by Broadcom — it requires the VM to be powered off, invalidates CBT for the next full backup, and must only be done with a validated backup in hand.

**Step 8 — Bulk remediation with PowerCLI (once the cause is understood).**
```powershell
# Force consolidation for every affected VM
(Get-VM -Name "<vm>").ExtensionData.ConsolidateVMDisks_Task()
# Or inventory-wide
Get-VM | Where-Object {$_.ExtensionData.Runtime.ConsolidationNeeded} |
  ForEach-Object { $_.ExtensionData.ConsolidateVMDisks_Task() }
```

**Step 9 — STOP CONDITION — chain inconsistency.**
If the chain is broken (missing parent, CID mismatch, descriptor invalid, `vmkfstools -e` errors), **stop consolidating**:
* Preserve all extents; copy the small descriptors (`.vmdk` text files) aside for analysis.
* Do not repoint the VM to an older delta (it discards writes newer than that point).
* Open a Broadcom support case; recovery options are (a) repair under support guidance, (b) restore from backup, or (c) clone from the tip of the chain with `vmkfstools` and attach the new disks after validation.

### B2.7 Verification of recovery

| # | Check | Pass criterion |
|---|---|---|
| V1 | VM Summary | `Virtual machine disks consolidation is needed` warning cleared |
| V2 | PowerCLI | `Get-VM \| Where-Object {$_.ExtensionData.Runtime.ConsolidationNeeded}` returns nothing for that VM |
| V3 | Datastore folder | Delta files for that VM are gone; only base disk + descriptor (+ current snapshot, if any) remain |
| V4 | Snapshot Manager | Consistent (either no snapshots, or only intended ones) |
| V5 | Backup | A backup of the VM completes successfully |
| V6 | Performance | Datastore latency and VM write throughput return to baseline |
| V7 | Capacity | Datastore free space stable/improved after the merge |

### B2.8 Rollback

| Situation | Action |
|---|---|
| Consolidation task hangs or fails mid-merge | Do **not** power off the VM mid-commit; let the task resolve or cancel it cleanly, capture the task error, and escalate with the descriptor files preserved |
| VM fails to power on after consolidation | Check for lock/stale task first (B1); if the chain is broken, restore from backup or follow the L3/Broadcom path |
| Storage vMotion or power-off step is not approved | Roll back to "contained" state: stop growth, keep the VM running, and schedule the offline consolidation window with the application owner |

### B2.9 Prevention

1. **Snapshot policy with teeth:** no snapshot older than 24–72 h; alert on snapshot age > 72 h and on more than 2–3 snapshots per VM.
2. **Maximum chain length:** stay well under 32 snapshots; monitor delta growth as a leading metric.
3. **Backup integration:** verify that the backup product removes its snapshots and hot-added disks on every path, including failures; alert on `ConsolidationNeeded`.
4. **Capacity alarms:** datastore free space ≥ 20–25%; an unmanaged delta must never be able to fill a datastore.
5. **Weekly inventory sweep:** run the PowerCLI consolidation/snapshot report (§B2.4) and remediate warnings before they become incidents.
6. **Avoid unnecessary quiescing:** fix VSS/VMware Tools issues rather than disabling quiescing silently; document any exception.
7. **Change-control snapshots:** require snapshot deletion evidence as part of change closure ("no snapshot left behind").

### B2.10 Anti-patterns

* Manually deleting `-000001.vmdk` or `-delta.vmdk` files, or editing descriptors by hand.
* Powering off a VM mid-consolidation "to speed it up".
* Running consolidation during peak I/O hours on a large VM without telling the application owner.
* Repointing a VM's configuration to an older delta to "fix" a broken chain.
* Leaving a fix-up snapshot in place "just in case" — it becomes the next incident.
* Assuming a backup protects you when backups are the tool that is failing on this VM.

### B2.11 References

* Broadcom KB **2003638** — *Virtual machine disks consolidation is needed* (symptom definition, standard Consolidate procedure, causes). *Verify the current article ID in the Broadcom KB portal before quoting it in a case.*
* Broadcom KB **1007969** — *The parent virtual disk has been modified since the child was created* (broken-chain symptoms and handling).
* Broadcom KB **1031873** — CBT/CTK issues and the disable-CBT workaround pattern.
* Broadcom KB — *Best practices for virtual machine snapshots in the VMware environment* (snapshot lifetime, max 32, delta growth).
* Broadcom KB — *Consolidating snapshots / deleting snapshots fails with "Failed to lock the file"* (lock-clearing path; cross-reference **B1**).
* Broadcom KB — *Insufficient space on datastore to consolidate snapshot* (space guidance, ≈1.5× snapshot size in the documented file-too-large scenario).

---

## B3. vMotion / Migration Fails — Compatibility Check, EVC, Network and Device Errors

| Attribute | Detail |
|---|---|
| SOP ID | **B3** |
| Default severity | **S3** (S2 if maintenance-mode evacuation or a DRS-driven evacuation is blocked) |
| Frequency | Common — especially after host hardware refresh, host patching, or VMware Tools/VM hardware upgrades |
| Typical MTTR | 15 min – 2 h (configuration causes); days if CPU incompatibility requires a power cycle or hardware change |
| Downtime | None for most fixes; a **power-off** is required for CPUID-mask and vCPU-count changes |
| Skills | L2 executes; L3 for EVC design decisions |
| Change required | Yes (host/cluster EVC changes and powered-off migrations) |

### B3.1 Trigger and symptoms

A migration (vMotion, Storage vMotion, DRS-driven, or maintenance-mode evacuation) fails. Capture the **exact** error — it tells you which of the five families you are in:

| Family | Typical error text |
|---|---|
| **CPU / EVC** | `Host CPU is incompatible with the virtual machine's requirements at CPUID level 0x1 register 'ecx'` · `The CPU of the host is incompatible with the CPU feature requirements of the virtual machine; problem detected at CPUID level 0x80000001 register 'edx'` · `The target host does not support the virtual machine's current hardware requirements ... MDS_NO is not supported / RSBA_NO is not supported / IBRS_ALL is not supported / RDCL_NO is not supported` · `To resolve CPU incompatibilities, use a cluster with Enhanced vMotion Compatibility (EVC) enabled` |
| **Network** | `Unable to migrate from <host> to <host>: The VMotion interface is not configured (or is misconfigured) on the destination host` |
| **Device / disk** | `Virtual Disk 'hard disk 0' is a mapped direct access LUN and its not accessible` · device-configuration messages for CD-ROM/floppy/serial/USB |
| **Resources / affinity** | `Virtual machine has CPU and/or memory affinities configured, preventing VMotion` · `Insufficient resources to satisfy configured failover level ...` (→ **B4**) |
| **Licensing** | `There are not enough Licenses installed to perform this operation` |

Also watch for migrations that start and then fail at 80–95% with network/timeout messages, or a VM object that exists on both hosts after a failed migration.

### B3.2 Impact

* **Blocked maintenance windows** — the single most disruptive consequence: host patching/hardware work cannot proceed.
* DRS cannot balance; capacity planning and planned failovers are blocked.
* Worst case: a migration fails mid-flight — verify that **only one instance** of the VM is running before doing anything else.

### B3.3 Root causes (ranked)

1. **Mixed CPU generations** in a cluster without EVC (or with the wrong EVC baseline) — including Intel↔AMD mixing, which is **not supported** for live migration.
2. **Per-VM CPUID mask set** (left over from a legacy migration, a template, or an upgrade) that no longer matches the destination host.
3. **Spectre/Meltdown patch asymmetry** between source and destination hosts (hosts at different patch levels exposing different CPU feature masks).
4. **vMotion VMkernel misconfiguration** — vMotion service not enabled on the destination vmk, wrong IP/port group, MTU mismatch, routing/firewall, or the port group missing on the destination host.
5. **Host-attached devices** — CD/DVD pointing at a host-local ISO, floppy, serial/file-backed devices, USB passthrough, host device passthrough.
6. **RDM / VMDK access issues** — the RDM LUN is not presented/masked identically on the destination.
7. **CPU or memory affinity** set on the VM, or reservations that the destination cannot satisfy.
8. **Licensing** that does not include vMotion (or hosts licensed at a level that does not permit it).

### B3.4 Evidence collection

```bash
# On source and destination ESXi hosts

# 1. CPU identity comparison (do this FIRST for any CPU-family error)
vsish -e cat /hardware/cpu/cpuList/0 | grep -i -E 'family|model|stepping|microcode|revision'
esxcli hardware cpu list | egrep -i 'model|speed|package' | head -20

# 2. Patch/build comparison (Spectre/Meltdown mask asymmetry)
vmware -v
esxcli system version get

# 3. vMotion VMkernel configuration on the destination
esxcli network ip interface list
esxcli network ip interface tag get -i vmk1        # expect: VMotion
esxcli network ip netstack list
# port group / vSwitch configuration
esxcli network vswitch standard portgroup list
esxcli network vswitch dvs vmware list

# 4. Reachability and MTU test from source to destination vMotion vmk
#    (use the tool your build supports; vmkping syntax/availability varies by release)
vmkping -I vmk1 -s 8972 -d <destination_vmotion_ip>
ping -I vmk1 <destination_vmotion_ip>

# 5. Device attachments and VM configuration
vim-cmd vmsvc/get.guest <vmid> | egrep -i 'cdrom|floppy|serial|usb'
grep -iE 'cdrom|floppy|serial|usb|scsi0:0.fileName' /vmfs/volumes/<ds>/<vm>/<vm>.vmx
```
In the vSphere Client:
* VM → **Monitor → Tasks and Events**: the failing migration task with the full error.
* VM → **Edit Settings → CPU → CPUID Mask → Advanced**: is a mask applied?
* VM → **Edit Settings → VM Options → Advanced → Configuration Parameters**: check for `cpuid.*` and `featMask.*` entries.
* **Cluster → Configure → VMware EVC**: current mode, and whether per-VM EVC is enabled.
* Datastore/disk mappings: confirm each disk and RDM is accessible from the destination host.

### B3.5 Immediate containment

1. **Never retry in a loop.** DRS may keep retrying and filling the task list; set the affected VM's DRS automation or cluster's DRS mode to **manual/partially automated** temporarily during triage so retries stop.
2. Confirm the VM is **running on exactly one host** (`esxcli vm process list` on both source and destination) after any partially completed migration. Two instances = stop and escalate (never power off either copy without L3/Broadcom guidance).
3. For maintenance windows blocked by one VM: document the exception, or use **powered-off migration** as the temporary path with the application owner's approval.

### B3.6 Resolution procedure

**Step 1 — CPU / EVC family.**

1. Compare CPU details between source and destination (B3.4 step 1). If the CPU families are Intel vs. AMD, **live migration is unsupported** — use a powered-off migration (and treat EVC design as the permanent fix).
2. Check the cluster EVC mode: **Cluster → Configure → VMware EVC**. The destination must be able to present at least the baseline the VM requires. If EVC is disabled or the baseline is wrong, enabling/raising EVC (in a maintenance window, hosts in maintenance mode as required) is the permanent fix.
3. Check for a **per-VM CPUID mask** and reset it:
   * Power off the VM (required).
   * **Edit Settings → CPU → CPUID Mask → Advanced → Reset All to Default** → OK.
   * Power on. The VM now reflects the correct EVC mode.
   * (For per-VM EVC instead of cluster EVC, set the VM's EVC baseline to match the cluster.)
4. Check for **advanced configuration parameters** left on the VM (`cpuid.*`, `featMask.*`, `monitor_control.*`). Remove stale ones — do not remove Spectre/Meltdown-related masks without understanding the patch asymmetry:
   * `featMask.vm.cpuid.stibp = "Max:0"`, `featMask.vm.cpuid.ibrs = "Max:0"`, `featMask.vm.cpuid.ibpb = "Max:0"` are the documented **workaround** for the Spectre/Meltdown patch-level mismatch (resolved in current vSphere releases — patch hosts instead of keeping the workaround).
5. If the VM requires features the destination cannot provide (`MDS_NO`, `RSBA_NO`, `IBRS_ALL`, `RDCL_NO`), the documented resolution is:
   * **Powered-off migration** (the VM must power-cycle to pick up the destination's feature set), and
   * **Enable EVC** (cluster-level or per-VM) as the permanent fix.
6. Confirm with a test migration after any change (B3.7).

**Step 2 — Network family.**

1. On the destination host, verify the vMotion VMkernel exists, is enabled, has a reachable IP, and is on the correct port group/VLAN:
   ```bash
   esxcli network ip interface list
   esxcli network ip interface tag get -i vmk<n>
   esxcli network ip netstack list
   ```
2. Verify MTU alignment end to end (jumbo frames require consistent configuration on vSwitch/vDS, uplinks, and physical switch ports). Test with large-packet payloads from the source vMotion vmk.
3. Verify the destination port group exists with the same name/VLAN (a missing or renamed port group is a classic post-DRS/migration failure), and that firewalls permit the vMotion traffic.
4. If vMotion is licensed per-host, confirm licensing on both hosts (Step 4).

**Step 3 — Device / disk family.**

1. In **Edit Settings**, remove or reconfigure host-attached devices before migrating:
   * CD/DVD-ROM → set to **Client Device** or detach; remove host-local ISO paths.
   * Floppy, serial (file/pipe/network), parallel, USB passthrough, host device passthrough → remove or switch to a migratable backing.
2. For **RDMs**: confirm the LUN is presented to the destination host with identical identity/masking, or convert to a VMDK (Storage vMotion with conversion) where the design allows.
3. Re-run the compatibility check (it now passes) and retry the migration.

**Step 4 — Resources, affinity and licensing family.**

1. Remove **CPU/memory affinity** from the VM (Edit Settings → CPU / Memory) — affinity pins the VM and is a common leftover from troubleshooting.
2. Check reservations/limits against destination capacity; right-size or migrate to a host with headroom.
3. Confirm the vSphere licensing level supports vMotion on both hosts and that the VM's hardware version is supported by the destination host build.
4. Re-run the migration.

**Step 5 — If the migration fails mid-flight (advanced).**
1. Confirm exactly one running instance.
2. Capture `vmware.log` from the source host and the destination host (`/var/run/log/hostd.log`, `vpxd.log` on the vCenter) around the failure time.
3. If a stale VM object remains on the destination with no running instance, do not delete it blindly — escalate to L3/Broadcom with the logs.

### B3.7 Verification of recovery

| # | Check | Pass criterion |
|---|---|---|
| V1 | Compatibility check | The migration task's pre-check passes with no CPU/device/network warnings |
| V2 | Live migration | A real vMotion completes and the VM keeps running (no reboot, no downtime observed by the application) |
| V3 | CPUID log | `vmware.log` shows no `CPUID differences from hostCPUID` errors after migration |
| V4 | Maintenance-mode evacuation | The host can be evacuated (the original business problem is solved) |
| V5 | EVC/graphics | VM Summary shows the expected EVC mode; no unexplained CPU masks remain |
| V6 | Post-patch state | Hosts in the cluster are at a consistent patch level (or the rationale for divergence is documented) |

### B3.8 Rollback

| Situation | Action |
|---|---|
| CPUID-mask reset caused guest problems | Restore the previous mask from the change record (mask settings are non-destructive to disk data); if the guest misbehaves, restore from backup and involve the application vendor |
| EVC change caused hosts to fail entering the cluster | Revert the EVC mode to the previous baseline; host-level EVC changes require hosts in maintenance mode — do this in a window |
| Powered-off migration was used and the application needs a clean restart | Follow the application's start-up validation checklist; the VM's virtual hardware is unchanged by the migration itself |

### B3.9 Prevention

1. **Adopt and standardise EVC** (cluster-level or per-VM) for every cluster; document the baseline and the hardware generations it supports.
2. **Never mix Intel and AMD hosts in the same cluster**; treat CPU generation changes as a design change with an EVC review.
3. **Standardise vMotion networking:** dedicated vmk, consistent MTU (document 1500 vs 9000 per cluster), consistent port group names on vDS, and monitoring on vMotion VMkernel errors.
4. **Patch hosts together** — avoid long-lived patch-level asymmetry across a cluster (the Spectre/Meltdown class of failure).
5. **Template hygiene:** ensure templates contain no CPUID masks, no affinities, no limits, no host-local device attachments.
6. **Remove host-attached devices** as part of VM build standards; validate with the pre-migration compatibility check before maintenance windows.
7. **Test migrations after every change** — host firmware/driver updates, cluster changes, and vCenter upgrades should be followed by a test vMotion of a canary VM.

### B3.10 Anti-patterns

* Enabling EVC "just to make it work" without checking the impact on running VMs (raise EVC, never lower it blindly on a live cluster).
* Leaving the Spectre/Meltdown `featMask` workaround in place instead of patching hosts.
* Removing host-attached devices by deleting files from the datastore.
* Setting CPU affinity permanently to work around a performance issue (it blocks DRS/vMotion and becomes the next outage).
* Ignoring a failed mid-flight migration and starting another attempt.

### B3.11 References

* Broadcom KB **1035834** — *vMotion fails during validation stage of migration with error: Compatibility Check Failure* (the master list: CPUID levels, the vMotion interface, affinity, NX flag, VT enablement, device/disk messages, licensing, RDM/VML mismatch).
* Broadcom KB **311754** — *vMotion fails during validation stage with error: Compatibility Check Failure* (host CPU feature set vs. destination; licensing; VMkernel networking; workaround = EVC).
* Broadcom KB **344646** — *Virtual machine migration fails due to EVC mode mismatch* (per-VM CPUID mask; Reset All to Default procedure; post-migration guest blue screens).
* Broadcom KB **390949** — *vMotion of VM fails with "The target host does not support the virtual machine's current hardware requirements"* (`MDS_NO`/`RSBA_NO`/`IBRS_ALL`/`RDCL_NO`; powered-off migration; enable EVC; `vsish` CPU comparison command).
* Broadcom KB **317715** — *vMotion fails to migrate between EVC clusters of ESXi hosts with the same configuration* (Spectre/Meltdown patching asymmetry; `featMask.vm.cpuid.*` workaround; resolved in 6.5 U2+).
* Broadcom KB — *Overview of migration compatibility error messages* (message-to-article index).
* Broadcom KB — *Ensuring Virtualization Technology (VT) is enabled on the VMware host*.

---

## B4. Power-On Blocked by vSphere HA — "Insufficient resources to satisfy configured failover level"

| Attribute | Detail |
|---|---|
| SOP ID | **B4** |
| Default severity | **S2** |
| Frequency | Common in tightly sized clusters, especially 2-node/3-node clusters and after reservations are added |
| Typical MTTR | 15 min (approved setting change) – hours (capacity/design fix) |
| Downtime | None; power-on is already failing |
| Skills | L2 executes; L3 for capacity design |
| Change required | Yes — **especially** to disable admission control (emergency change with an expiry) |

### B4.1 Trigger and symptoms

* Powering on a VM fails with: `Insufficient resources to satisfy configured failover level for vSphere HA.`
* Cluster banner/warning: `Insufficient configured resources to satisfy the desired vSphere HA failover level on the cluster`.
* The same error can appear on a **vMotion into the cluster**, on a **reservation change**, or after an ESXi host goes `not responding` and remaining resources cannot absorb the failover guarantee.
* Cluster → **Monitor → vSphere HA** shows current failover capacity below the desired capacity, and/or the Current Failover Level dropping to zero.

**What is really happening:** Admission Control is a safety feature. It refuses an operation that would consume the reserved capacity needed to restart VMs after a host failure. The error is *correct behaviour*; the question is whether the design (or a misconfiguration) is wrong.

### B4.2 Impact

* VMs that are already running are unaffected — but any restart, planned failover, or power-on is blocked.
* Maintenance windows, DR tests, and application deployments are blocked cluster-wide (not just for one VM).
* Temporary "disable admission control" workarounds that are never reverted silently remove the HA restart guarantee — a latent risk that must be tracked.

### B4.3 Root causes (ranked)

1. **Genuine capacity exhaustion** — the cluster cannot lose a host and still restart the workload.
2. **Slot-policy slot size inflated by a single oversized reservation** (Slot Policy / "Host Failures Cluster Tolerates"): one VM with a very large CPU or memory reservation inflates the slot, so the cluster cannot fit the required number of slots.
3. **Desired failover level misaligned with the cluster design** — e.g. 50% reserved on a 10-host cluster requires 5 empty hosts, i.e. more than an N+4 intent; the correct figure is `(hosts to tolerate ÷ total hosts) × 100`.
4. **Two-node cluster host count mismatch** — vCenter believes the cluster has more/fewer hosts than reality (e.g. `numHosts` inconsistency in FDM logs) so the calculation is wrong despite apparent capacity.
5. **Dedicated Failover Host policy violations** — the designated failover host is running VMs, in maintenance mode, or disconnected.
6. **The cluster is over-committed by reservations** (not by actual usage) — reservations from resource pools and templates accumulate invisibly.
7. **A recent host loss or an over-large VM deployed into a constrained cluster.**

### B4.4 Evidence collection

In the vSphere Client:
* **Cluster → Monitor → vSphere HA**: current failover capacity vs. desired; reserved failover CPU/memory; slot size and slots used/available (for slot policy).
* **Cluster → Configure → vSphere Availability → Edit → Admission Control**: which policy is in force (Host Failures Cluster Tolerates / Cluster Resource Percentage / Dedicated Failover Hosts) and its values.
* **Cluster → Configure → Resource Allocation**: find the largest CPU/memory **reservations** (VMs and resource pools).
* **Cluster → Monitor → vSphere DRS / Tasks**: is DRS balancing or blocked by rules/affinity?

```bash
# On an ESXi host in the cluster: FDM (HA agent) logs
grep -iE 'numHosts|failover|slot|admission' /var/log/fdm.log | tail -50
```
```powershell
# PowerCLI quick view
Get-Cluster | Select-Object Name,HAEnabled,HAAdmissionControlEnabled
(Get-Cluster "<cluster>" | Get-View).Summary.CurrentFailoverLevel       # current failover level
Get-VMHost -Location "<cluster>" | Select-Object Name,ConnectionState,
  @{n='CpuMhz';e={$_.CpuTotalMhz}}, @{n='MemGB';e={[math]::Round($_.MemoryTotalGB,1)}}
Get-VM | Where-Object {$_.ExtensionData.ResourceConfig.MemoryAllocation.Reservation -gt 0 -or
                       $_.ExtensionData.ResourceConfig.CpuAllocation.Reservation -gt 0} |
  Select-Object Name,NumCpu,MemoryGB,
    @{n='CpuResMhz';e={$_.ExtensionData.ResourceConfig.CpuAllocation.Reservation}},
    @{n='MemResMB';e={$_.ExtensionData.ResourceConfig.MemoryAllocation.Reservation}} |
  Sort-Object MemResMB -Descending
```

### B4.5 Immediate containment

1. **Do not disable admission control as a first action.** It is the last resort (B4.6 step 5) because it removes the restart guarantee.
2. Free capacity by less invasive means first: vMotion VMs off the most loaded host, power off non-production VMs, or temporarily reduce the reservations of non-critical VMs (a reversible, documented action).
3. If a business-critical VM must start **now** and capacity exists, the fastest safe path is usually to reduce a large non-critical reservation — not to change the policy.

### B4.6 Resolution procedure

**Step 1 — Confirm the policy in force and read the numbers.**
Cluster → **Configure → vSphere Availability → Edit → Admission Control**. Record: policy, "Host failures cluster tolerates" or the reserved percentage, and whether an override is in place. Then read **Monitor → vSphere HA** for current vs. desired capacity.

**Step 2 — Fix genuine capacity exhaustion (preferred).**
* Add one or more ESXi hosts to the cluster (the definitive fix).
* Reduce/remove **reservations** on non-critical VMs (reservations should exist only where the application genuinely needs guaranteed resources).
* Right-size the workloads occupying the cluster (memory/CPU over-allocation by configuration).
* Re-check current failover capacity — it should now exceed the desired figure.

**Step 3 — Fix slot-size inflation (Slot Policy clusters).**
* Identify the VM or resource pool that sets the largest reservation (B4.4 query).
* Reduce that reservation, or split the workload, so the slot shrinks.
* Where the design requires it, adjust the slot-size advanced settings (`das.slotcpuinmhz`, `das.slotmeminmb`) in a controlled change — documenting that this changes the failover guarantee. (L3 decision.)

**Step 4 — Align the desired failover level with the design.**
* Compute the intended percentage: `(number of host failures to tolerate ÷ total number of hosts) × 100`. Example: 4 failures in a 10-host cluster = 40%.
* Set **Override calculated failover capacity** to that figure (Configure → vSphere Availability → Edit → Admission Control → Cluster resource Percentage).
* Remember the UI will silently revert a value it cannot satisfy with existing reservations — if lowering the percentage does not stick, reservations are consuming the capacity and Step 2 applies.

**Step 5 — Last resort: disable admission control (emergency change with an expiry).**
1. **Requires a change record and an explicit expiry time.**
2. Cluster → Configure → **vSphere Availability** → Edit → **Admission Control** → set *Define host failover capacity by* to **Disable**.
3. Power on the VM and restore service to the business.
4. **Immediately record** the change in the incident record and create a follow-up task with an owner and due date.
5. **Re-enable admission control** as soon as capacity permits (same change window if possible), and re-run the B4.7 verification.
6. Ensure monitoring detects "admission control disabled" events — an un-reverted disable is a security/availability regression.

**Step 6 — Two-node cluster host-count mismatch (documented fix).**
If the numbers do not add up (apparent capacity, yet the error persists) and FDM logs suggest an incorrect host count:
* Remove the affected host from vCenter and add it back (Broadcom-documented remedy for the `numHosts` mismatch class), or
* Disable and re-enable HA on the cluster (after verifying FDM logs).
Both operations are disruptive to HA state — do them in a window with L3 oversight.

**Step 7 — Dedicated Failover Host policy.**
* Confirm the designated failover host is **empty, connected, and not in maintenance mode** (DRS will not place VMs there, but manual operations can).
* vMotion any VMs off it, then re-check the admission-control state.

### B4.7 Verification of recovery

| # | Check | Pass criterion |
|---|---|---|
| V1 | Power-on | The VM powers on successfully |
| V2 | Admission control state | Desired capacity ≤ current capacity (no error banner) |
| V3 | `CurrentFailoverLevel` | ≥ the documented N+X intent for the cluster |
| V4 | Failover host (if used) | Empty, connected, not in maintenance mode |
| V5 | Temporary changes reverted | Admission control is enabled; no lingering "Disable" setting; the associated change task is closed |
| V6 | Capacity alerting | Monitoring reports the cluster's headroom trend (see Prevention) |
| V7 | HA functionality | Test by placing a non-production host in maintenance mode (or simulating a failure per your DR runbook) and confirming HA restarts VMs as designed |

### B4.8 Rollback

| Situation | Action |
|---|---|
| Reducing reservations caused application problems | Restore the previous reservation values from the change record; a reservation change does not move data, so this is quickly reversible |
| Changing the percentage produced insufficient protection | Restore the previous setting; the real fix is capacity, so schedule the purchase/expansion |
| Host remove/re-add made HA worse | Re-enable HA on the cluster; if FDM does not reinitialize, escalate to L3/Broadcom with `/var/log/fdm.log` |
| Admission control was disabled and not restored | Treat as an open incident: restore it in the next window, and record the exposure duration in the incident file |

### B4.9 Prevention

1. **Capacity governance:** maintain a documented N+X intent per cluster, with headroom modelled for the HA guarantee, not just for current usage.
2. **Reservation hygiene:** quarterly review of CPU/memory reservations; templates must not carry reservations; require justification for new reservations.
3. **Alert on headroom, not just on failure:** alert when `CurrentFailoverLevel` approaches the desired level (and never let it sit at zero).
4. **Detect admission-control changes:** alert on the vSphere event that fires when admission control is disabled/reconfigured — this catches both mistakes and un-reverted workarounds.
5. **Dedicated failover host policy:** monitor that the failover host stays empty; alert if VMs are placed on it.
6. **Slot policy review:** document why slot policy was chosen; if reservations vary widely, prefer Cluster Resource Percentage.
7. **DR/HA testing:** annual test of actual failover so the guarantee is real, not theoretical.

### B4.10 Anti-patterns

* Disabling admission control permanently because "it keeps blocking deployments".
* Setting a very high percentage "for safety" without checking it against the cluster size (50% on 10 hosts = half the cluster must stay empty).
* Adding huge reservations to VMs "to guarantee performance" — you are consuming the failover buffer.
* Leaving a two-node cluster misconfiguring host counts after a rebuild.
* Fixing the symptom for one VM while leaving the cluster cluster-wide risk unaddressed.

### B4.11 References

* Broadcom KB **421814** — *"Insufficient resources to satisfy configured failover level for vSphere HA" error when Powering ON a Virtual Machine* (reservation vs. failover guarantee conflict; capacity/reservation/percentage options; documented temporary disable path).
* Broadcom KB **424373** — *Error: Insufficient configured resources to satisfy the desired vSphere HA failover level on the cluster* (desired vs. current failover capacity; the `(failures ÷ hosts) × 100` formula; where to set the override).
* Broadcom KB **301492** — Two-node cluster HA "insufficient resources" caused by an incorrect host count (`numHosts`) — remove and re-add the host. *Confirm the current article number in the Broadcom KB portal.*
* Broadcom TechDocs — *vSphere Availability → Admission Control* (policy definitions: Host Failures Cluster Tolerates, Cluster Resource Percentage, Dedicated Failover Hosts).
* Broadcom TechDocs — *vSphere Resource Management* (reservations, shares, limits and their effect on admission control).

---

## B5. VM Performance Degradation — CPU Ready, Memory Contention, Storage Latency

| Attribute | Detail |
|---|---|
| SOP ID | **B5** |
| Default severity | **S3** (S2 if a business-critical application SLA is breached; S2 with a defined timescale when ready-time or swap is severe) |
| Frequency | Very common — the "the VM is slow" ticket |
| Typical MTTR | 1–4 h to a diagnosis and first improvement; days for full right-sizing cycles |
| Downtime | None for most actions; reducing vCPU/memory requires a **power cycle** |
| Skills | L2 executes; L3 for cluster-level design and capacity |
| Change required | Yes for vCPU/RAM changes; no for host/placement corrections (still logged) |

### B5.1 Trigger and symptoms

* Users report application latency, timeouts, or batch jobs overrunning — while the **guest OS looks idle** (low in-guest CPU).
* vSphere Client performance charts show high CPU ready time, memory ballooning/swap, or elevated disk latency.
* Monitoring alerts on `%RDY`, co-stop, balloon, swap rate, or datastore latency.
* May correlate with a recent change: new VMs on the host, a VM added to a cluster, a backup window, or a storage path event.

**Cardinal rule:** diagnose with data from **three layers** — guest, VM (vSphere), and host/datastore — before changing anything. "Slow VM" is a symptom, not a cause.

### B5.2 The metrics that matter (and how to read them)

**CPU ready (the single most misunderstood metric).** `cpu.ready.summation` is reported in milliseconds and must be converted to a percentage using the chart interval (Broadcom KB 2002181):

| Chart interval | Interval seconds | Quick conversion (summation ÷ divisor) |
|---|---|---|
| Realtime | 20 s | **÷ 200** |
| Past Day | 300 s | **÷ 3000** |
| Past Week | 1 800 s | **÷ 18000** |
| Past Month | 7 200 s | **÷ 72000** |
| Past Year | 86 400 s | **÷ 864000** |

Formula: `CPU ready % = (ready_summation_ms ÷ (interval_seconds × 1000)) × 100`.

**Multi-vCPU VMs:** divide the resulting percentage by the number of vCPUs to get the **per-vCPU** ready time. In vSphere 6 and later, the "CPU Readiness" chart value is already per-vCPU, while esxtop's `%RDY` shows the raw summation-derived percentage — know which one you are reading, or you will mis-size VMs in both directions.

**Thresholds (per-vCPU), as a working standard:**

| Per-vCPU ready | Interpretation | Action |
|---|---|---|
| < 2 % | Normal; appropriate for latency-sensitive workloads (databases, VDI, real-time) | None |
| 2–5 % | Early contention | Investigate placement and sizing |
| 5–10 % | Performance impact | Right-size or rebalance now |
| > 10 % | Production incident | Emergency: rebalance capacity; combine with host CPU > 85 % to confirm overcommitment |

**Supporting CPU metrics:**

| Metric | Meaning | Threshold / interpretation |
|---|---|---|
| `cpu.costop.summation` (**%CSTP**) | Co-scheduling overhead for multi-vCPU VMs — the "you gave it too many vCPUs" indicator | > 3 % sustained = oversizing; adding vCPUs will make it **worse** |
| `cpu.maxlimited.summation` (**%MLMTD**) | The VM is throttled by a **CPU limit** (usually inherited from a template or resource pool; invisible to the guest) | Any non-zero value where the user reports slowness = misconfiguration |
| Host `cpu.usage.average` | Host-level compute pressure | Sustained > 85 % with ready > 5 % = genuine overcommitment |
| NUMA locality (esxtop `m` screen, `N%L`) | Memory locality for large VMs | < 80 % on latency-sensitive VMs = investigate sizing/NUMA |

**Memory metrics:**

| Signal | Meaning | Action |
|---|---|---|
| Balloon (`mem.vmmemctl.average`, esxtop memory screen) | Host is reclaiming guest memory — guest has more RAM than the host can back | Reduce memory overcommit, add RAM, or right-size |
| Swap in/out (`mem.swapinRate`, `mem.swapoutRate`, esxtop `SWR/s` / `SWW/s`) | Host memory exhaustion (severe) | Treat as an incident — swap destroys latency |
| Host memory utilization | Sustained high host memory (with any ballooning/swap) | Rebalance with DRS / add capacity |

**Storage metrics (esxtop disk screen, or vSphere charts):**

| Metric | Meaning | Threshold guidance |
|---|---|---|
| `DAVG/cmd` | Device latency | > 20 ms = investigate; > 40–50 ms = severe for typical VMFS workloads |
| `KAVG/cmd` | ESXi kernel (queue/throttle) latency | Consistently high = queue depth, throttling, or path saturation |
| `GAVG/cmd` | Guest-observed latency (KAVG + DAVG) | Track against the application's tolerance |
| Path state / APD-PDL events | Storage path failures | Any `Dead`/`Off` path or APD event is an incident (escalate) |

### B5.3 Evidence collection

In the vSphere Client (VM → **Monitor → Performance → Advanced**):
* `cpu.ready.summation` (convert per B5.2), `cpu.costop.summation`, `cpu.maxlimited.summation`
* `mem.vmmemctl.average`, `mem.swapinRate`, `mem.swapoutRate`, `mem.overhead`
* `virtualDisk.totalReadLatency` / `totalWriteLatency`, `datastore.totalReadLatency`, `datastore.numberReadAveraged`
* Compare the **same window** before and after any change.

On the ESXi host:
```bash
esxtop
#   c -> CPU screen: %RDY, %CSTP, %MLMTD, %USED per VM world (press 'v' to show only VMs)
#   m -> memory screen: balloon, swap in/out rates, and host memory state
#   d -> disk screen: DAVG/cmd, KAVG/cmd, GAVG/cmd per device
#   f -> add/remove fields; 'V' to clear non-VM worlds; 's'/'#V' tweaks
```
```bash
# Host-level context
esxcli hardware memory get
esxcli hardware cpu global get
esxcli storage core path list | egrep -i 'state|naa' | head -40
esxcli storage core device list | egrep -i 'Display Name|Status|Size' | head -60
vmware -v                                     # build, for known-issue checks
```
```powershell
# PowerCLI: ready time (realtime) and the biggest consumers
Get-VM -Name "<vm>" | Get-Stat -Stat cpu.ready.summation -Realtime -MaxSamples 12
Get-VM -Name "<vm>" | Get-Stat -Stat cpu.costop.summation -Realtime -MaxSamples 12
Get-VMHost -Location "<cluster>" | Sort-Object -Property CpuUsageMhz -Descending |
  Select-Object Name,CpuUsageMhz,CpuTotalMhz,MemoryUsageGB,MemoryTotalGB | Format-Table
```

Guest-side checks: installed VMware Tools version and status, in-guest CPU/memory/disk counters, antivirus scan windows, storage controller driver type (PVSCSI/LSI), and application-level bottlenecks (a slow application with idle CPU is often **not** a hypervisor problem).

### B5.4 Immediate containment

1. **Prove the layer.** Guest CPU low + VM ready high = hypervisor contention. Guest CPU high = the guest/application is busy (not a vSphere issue). Guest idle + no ready and no balloon/swap + high disk latency = storage.
2. **Relieve contention quickly (non-disruptive):**
   * vMotion the VM to a host with headroom (verify destination fit, then monitor ready).
   * vMotion other VMs off the busy host.
   * Remove an inherited **CPU limit** (this is non-disruptive and often the "instant fix"): Edit Settings → CPU → *Limit* → reset, and check the parent resource pool.
3. **Do not** add vCPUs as a reflex — if `%CSTP` is elevated, adding vCPUs worsens the problem.

### B5.5 Resolution procedure

**Step 1 — CPU contention: rebalance and right-size.**
1. Confirm per-vCPU ready (converted correctly) and host CPU utilization.
2. Rebalance with vMotion/DRS (partially automated or manual for control). Confirm the destination host has lower CPU ready for comparable VMs.
3. **Right-size the guest:** reduce the vCPU count for oversized VMs (power cycle required). Best practice: start small and add vCPUs based on measured guest CPU demand — reducing vCPUs requires a power cycle, adding does not, so over-provisioning is a one-way trap.
4. Remove **CPU limits** wherever the guest is being throttled (`%MLMTD` non-zero) and remove stale shares/limits inherited from templates.
5. Consider host power management settings — a "Balanced" BIOS/OS policy can increase latency tails for latency-sensitive workloads; the "High Performance" profile is often justified for database hosts (document the power/cost trade-off).

**Step 2 — Memory pressure: stop the bleeding, then size correctly.**
1. If ballooning or swapping is present, treat it as an outage-grade issue: vMotion the VM to a host with memory headroom immediately.
2. **Right-size memory**: increase the VM's memory (or reduce vRAM where the guest does not need it) so the host is not overcommitted; production hosts should be sized so that balloon/swap stays at zero.
3. Check for memory **limits** and reservations on the VM and its resource pool.
4. Confirm the host's memory is not consumed by other workloads (check the top consumers and DRS balance).

**Step 3 — Storage latency: find the source.**
1. Determine whether latency is device-side (`DAVG`), kernel/queue-side (`KAVG`), or path-related.
2. Check for **snapshots** on the VM — a long delta chain amplifies writes (fix via **B2**).
3. Check path health and any APD/PDL events; escalate dead paths to the storage/network team immediately.
4. Check for storage congestion: enable/verify **SIOC** on the datastore, verify queue depth, and identify noisy neighbours (per-VM IOPS/latency).
5. Distribute load: Storage vMotion heavy VMs to less-loaded datastores; avoid placing multiple I/O-heavy VMs on the same limited LUN.
6. Confirm paravirtual drivers (VMXNET3, PVSCSI where supported) and current VMware Tools in the guest.
7. Validate that the array is not the bottleneck (vendor-side metrics) — vSphere can only report.

**Step 4 — NUMA and oversizing (large VMs).**
1. For VMs with a vCPU/RAM footprint larger than one physical NUMA node, check locality (`N%L` in esxtop `m` screen).
2. Prefer sizing the VM to fit a NUMA node; if not possible, ensure the host's NUMA scheduler is operating normally and consider a host with larger nodes.
3. Use "Cores per socket" to keep a VM within a single NUMA node where the guest licensing allows it.

**Step 5 — Guest/application layer (do not skip).**
1. Verify VMware Tools is installed, current, and running.
2. Check antivirus exclusions for VMware/backup paths and application data directories.
3. Check the storage controller type and driver, and the virtual hardware version (older hardware limits performance features).
4. Check in-guest paging/swap, application thread pools, and scheduled jobs (backups, indexing, scans) that coincide with the degradation window.

### B5.6 Verification of recovery

| # | Check | Pass criterion |
|---|---|---|
| V1 | Per-vCPU ready | < 2–5 % sustained over the same measurement window |
| V2 | Co-stop | `%CSTP` < 3 % (near zero on correctly sized VMs) |
| V3 | Limits | `%MLMTD` = 0 (no throttling) |
| V4 | Memory | No ballooning, no swap in/out; host memory has headroom |
| V5 | Storage | `DAVG` and `GAVG` for the VM's datastore back to baseline (< 20 ms guidance) |
| V6 | Application | The application owner confirms the SLA/latency improvement (the only verification that truly counts) |
| V7 | Trend | 24–72 h of charts show the improvement is sustained, not a one-off |

### B5.7 Rollback

| Situation | Action |
|---|---|
| vCPU/RAM reduction caused worse performance | Power off, restore the previous vCPU/RAM values (changes require a power cycle), and re-analyse with the correct per-vCPU conversion |
| vMotion moved the problem | Move the VM back or to a third host; document the host's contention as a capacity issue |
| Removing a limit caused contention for other VMs | Restore the limit and instead fix the underlying sizing/placement; a limit is a symptom-management tool, but it may be required as an interim control |
| Storage vMotion did not improve latency | Validate at the array as well; latency may be fabric/array-side |

### B5.8 Prevention

1. **Monitor the right signals at the right thresholds** (Appendix D): per-vCPU ready time, co-stop, balloon/swap, datastore latency, host CPU/memory.
2. **Right-size at provisioning:** no vCPU inflation, no unjustified reservations (they also consume the HA buffer — see B4), no inherited limits in templates.
3. **Capacity reviews quarterly**, correlating host CPU/memory headroom with ready-time trends and admission-control headroom.
4. **Snapshot hygiene** (B2) and backup scheduling so that merge windows do not coincide with business peaks.
5. **Standardise on paravirtual drivers and current VMware Tools** and keep VM hardware versions current.
6. **Baseline before you need it:** record normal ready-time/latency figures for tier-1 VMs so anomalies are obvious.
7. **Application-owner dialogue:** performance incidents are resolved fastest when the storage, hypervisor, guest, and application layers are all instrumented.

### B5.9 Anti-patterns

* Reading raw `cpu.ready.summation` and comparing it to a "5 %" threshold without applying the interval divisor (the single most common misdiagnosis).
* Adding vCPUs to a VM with high `%CSTP` (guaranteed to worsen co-scheduling).
* Setting CPU/memory **limits** and forgetting them; limits propagate through templates and pools and silently throttle workloads.
* Overcommitting production memory and calling ballooning "normal".
* Chasing storage latency inside the VM while the array/fabric is the real bottleneck.
* Treating "guest CPU is low" as proof that the hypervisor is at fault — check ready, co-stop, balloon, and latency first.

### B5.10 References

* Broadcom KB **2002181** — *CPU ready time* — chart intervals and the summation-to-percentage conversion (Realtime ÷ 200, Past Day ÷ 3000, Week ÷ 18000, Month ÷ 72000, Year ÷ 864000); per-vCPU adjustment guidance.
* Broadcom KB **1005362** — Troubleshooting high CPU ready / `%CSTP` and vCPU-count reduction guidance (*verify the current article ID in the Broadcom KB portal*).
* Broadcom TechDocs — *vSphere Monitoring and Performance* (metric definitions: CPU ready, co-stop, balloon, swap, datastore latency).
* Broadcom TechDocs — *vSphere Resource Management* (shares, reservations, limits; NUMA and cores-per-socket guidance).
* Broadcom TechDocs — *Performance Best Practices for VMware vSphere* (power management, paravirtual drivers, sizing).
* Broadcom KB — *Virtual machine performance charts and how to read them* / *Interpreting esxtop statistics*.

---
---

# APPENDICES

---

## Appendix A — Command & Evidence Cheat Sheet

### A.1 vCenter Server Appliance (SSH as `root`)

| Task | Command |
|---|---|
| Service status (all) | `service-control --status --all` |
| Restart one service | `service-control --stop <svc> && service-control --start <svc>` |
| Restart everything | `service-control --stop --all && service-control --start --all` |
| Certificate manager | `/usr/lib/vmware-vmca/bin/certificate-manager` |
| vCert (7.x/8.x, recommended) | `./vCert.py` (menus: 1 status, 3 manage, 4 trust anchors, 8 restart services) |
| All certificate stores + expiry | `for store in $(/usr/lib/vmware-vmafd/bin/vecs-cli store list \| grep -v TRUSTED_ROOT_CRLS); do echo "[*] Store :" $store; /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store --text \| grep -ie "Alias" -ie "Not After"; done;` |
| Disk/inode usage | `df -h; df -i` |
| Storage consumption by area | `du -sh /storage/* \| sort -h; du -sh /var/log/vmware/* \| sort -h` |
| VCDB access | `/opt/vmware/vpostgres/current/bin/psql -U postgres -d VCDB` |
| Backup log | `tail -300 /var/log/vmware/applmgmt/backup.log` |
| Support bundle | VAMI → Support → Generate support bundle, or the `vc-support` utility (check `--help` on your build) |
| Time/NTP | `timedatectl status; chronyc sources` |
| Name resolution | `hostname -f; getent hosts "$(hostname -f)"` |

### A.2 ESXi host (SSH as `root`)

| Task | Command |
|---|---|
| Version/build | `vmware -v; esxcli system version get` |
| Running VMs + world IDs | `esxcli vm process list` |
| All registered VMs | `vim-cmd vmsvc/getallvms` |
| Datastores | `esxcli storage filesystem list` |
| Device/path state | `esxcli storage core device list; esxcli storage core path list` |
| Lock owner (file) | `vmfsfilelockinfo -p /vmfs/volumes/<ds>/<vm>/<file>` |
| Lock owner (host MAC) | `vmkfstools -D /vmfs/volumes/<ds>/<vm>/<vm>-flat.vmdk` |
| Process holding a file | `lsof \| egrep 'Cartel\|<file>'` |
| Snapshot chain trace | `vmkfstools -q -v 10 /vmfs/volumes/<ds>/<vm>/<vm>.vmdk` |
| Chain consistency | `vmkfstools -e /vmfs/volumes/<ds>/<vm>/<disk>.vmdk` |
| Restart management agents | `services.sh restart` |
| Performance | `esxtop` (`c` CPU, `m` memory, `d` disk; `%RDY`, `%CSTP`, `%MLMTD`, `DAVG`, `KAVG`, `GAVG`) |
| CPU comparison for vMotion | `vsish -e cat /hardware/cpu/cpuList/0 \| grep -i -E 'family\|model\|stepping\|microcode\|revision'` |
| HA agent log | `/var/log/fdm.log` |
| Host support bundle | `vm-support -w /vmfs/volumes/<healthy_ds>` |
| VOMA (L3/Broadcom only) | `voma -m vmfs -f dump -d /vmfs/devices/disks/naa.<id>:1 -D <out>` / `voma -m vmfs -f check -a -d ... -s ...` |

### A.3 PowerCLI (admin workstation)

```powershell
Connect-VIServer vcsa.example.com -User administrator@vsphere.local

# --- vCenter / inventory health
Get-VMHost | Select-Object Name,ConnectionState,Version,Build
Get-Cluster | Select-Object Name,HAEnabled,DRSEnabled
(Get-Cluster "<cluster>" | Get-View).Summary.CurrentFailoverLevel

# --- Snapshot and consolidation hygiene
Get-VM | Where-Object {$_.ExtensionData.Runtime.ConsolidationNeeded} | Select-Object Name,PowerState
Get-VM | Get-Snapshot | Where-Object {$_.Created -lt (Get-Date).AddDays(-3)} |
  Select-Object VM,Name,Created,@{n='SizeGB';e={[math]::Round($_.SizeGB,2)}} | Sort-Object Created

# --- Over-reservation audit (also feeds the HA admission-control review, B4)
Get-VM | Where-Object {$_.ExtensionData.ResourceConfig.MemoryAllocation.Reservation -gt 0 -or
                       $_.ExtensionData.ResourceConfig.CpuAllocation.Reservation -gt 0} |
  Select-Object Name,NumCpu,MemoryGB,
    @{n='CpuResMhz';e={$_.ExtensionData.ResourceConfig.CpuAllocation.Reservation}},
    @{n='MemResMB';e={$_.ExtensionData.ResourceConfig.MemoryAllocation.Reservation}} |
  Sort-Object MemResMB -Descending

# --- Datastore headroom
Get-Datastore | Select-Object Name,
  @{n='FreeGB';e={[math]::Round($_.FreeSpaceGB,1)}},
  @{n='CapGB';e={[math]::Round($_.CapacityGB,1)}} | Sort-Object FreeGB

# --- Performance spot-check (conversion per Broadcom KB 2002181 is a manual step; see B5.2)
Get-VM -Name "<vm>" | Get-Stat -Stat cpu.ready.summation -Realtime -MaxSamples 12
Get-VM -Name "<vm>" | Get-Stat -Stat cpu.costop.summation -Realtime -MaxSamples 12
```
> PowerCLI property names vary between releases; validate any script against a non-production vCenter before using it in an incident.

---

## Appendix B — Support Bundle & Escalation Data-Collection Checklist

Collect **all** of the following before opening or updating a Broadcom SR. Missing evidence is the single biggest cause of slow vendor resolution.

| # | Item | How to collect |
|---|---|---|
| 1 | vCenter support bundle | VAMI → Support → Generate support bundle (start it early; it takes time) |
| 2 | ESXi support bundles (affected hosts) | `vm-support -w /vmfs/volumes/<healthy_ds>` on each host |
| 3 | Exact error text (screenshot + copy/paste) | vSphere Client task/event, browser, VAMI |
| 4 | `service-control --status --all` output | VCSA |
| 5 | `df -h` / `df -i` output | VCSA (all partitions) |
| 6 | Certificate inventory output (A1.4 step 6) | VCSA |
| 7 | Relevant service logs (last 300 lines each) | `/var/log/vmware/vpxd/vpxd.log`, `vmcad/certificate-manager.log`, `sso/`, `sts/`, `vmdird/`, `vmon/`, `applmgmt/backup.log`, `vcha/` |
| 8 | ESXi logs for the window | `/var/log/vmkernel.log`, `/var/log/hostd.log`, `/var/log/vpxa.log`, `/var/log/fdm.log` |
| 9 | VM-level log | `/vmfs/volumes/<ds>/<vm>/vmware.log` (for B1/B2/B3) |
| 10 | Snapshot chain listing (B2) | Folder listing + `vmkfstools -q -v 10` + descriptor files |
| 11 | Lock evidence (B1) | `vmfsfilelockinfo`, `vmkfstools -D`, `lsof`, `esxcli vm process list` |
| 12 | Admission-control/cluster state (B4) | Screenshots of vSphere HA monitor + admission control settings, `CurrentFailoverLevel` |
| 13 | Performance charts (B5) | Exported charts/screenshots for the same window, before/after |
| 14 | Timeline | First symptom, first alert, actions taken with timestamps |
| 15 | Change history | vCenter/host patches, DNS/firewall/certificate changes in the preceding 30 days |
| 16 | Environment facts | vCenter build, ESXi builds, appliance size, inventory scale, backup product/version |

**Escalation content template (for the SR header):**

```
Impact:        <S1/S2> — <business function blocked> — <number of VMs/hosts>
Environment:   vCenter <version/build>, ESXi <version/build>, <appliance size>, <ELM/VCHA?>
Symptom:       <one sentence, exact error string>
Timeline:      <first occurrence> → <actions> → <current state>
Evidence:      <bundle names, log files, command outputs attached>
Workaround:    <applied?>, <business impact of workaround>
Question:      <specific ask — "is this a known defect with a fix?" / "confirm advfix scope">
```

---

## Appendix C — Inventory Health Script (Weekly Prevention Sweep)

Run weekly (read-only) and record the output against the change log. This single script covers the leading indicators for **A1, A3, A5, B2 and B4**.

```powershell
<# weekly-vsphere-health.ps1 - read-only inventory sweep #>
Connect-VIServer vcsa.example.com -User administrator@vsphere.local

"=== vCenter / host state ==="
Get-VMHost | Select-Object Name,ConnectionState,Version,Build | Format-Table -AutoSize

"=== VMs needing consolidation (B2) ==="
Get-VM | Where-Object {$_.ExtensionData.Runtime.ConsolidationNeeded} | Select-Object Name,PowerState

"=== Snapshots older than 72h (B2) ==="
Get-VM | Get-Snapshot | Where-Object {$_.Created -lt (Get-Date).AddDays(-3)} |
  Select-Object VM,Name,Created,@{n='SizeGB';e={[math]::Round($_.SizeGB,2)}} | Sort-Object Created

"=== Datastores below 25% free (A3/B2) ==="
Get-Datastore | Where-Object {$_.FreeSpaceGB / $_.CapacityGB -lt 0.25} |
  Select-Object Name,@{n='FreeGB';e={[math]::Round($_.FreeSpaceGB,1)}},
                @{n='FreePct';e={[math]::Round(100*$_.FreeSpaceGB/$_.CapacityGB,1)}}

"=== Clusters: HA state and failover headroom (B4) ==="
Get-Cluster | ForEach-Object {
  $c = Get-View $_.Id
  [pscustomobject]@{
    Cluster            = $_.Name
    HAEnabled          = $c.ConfigurationEx.DasConfig.Enabled
    AdmissionControl   = $c.ConfigurationEx.DasConfig.AdmissionControlEnabled
    CurrentFailoverLvl = $c.Summary.CurrentFailoverLevel
  }
} | Format-Table -AutoSize

"=== Over-reservation audit (B4) ==="
Get-VM | Where-Object {$_.ExtensionData.ResourceConfig.MemoryAllocation.Reservation -gt 0 -or
                       $_.ExtensionData.ResourceConfig.CpuAllocation.Reservation -gt 0} |
  Select-Object Name,NumCpu,MemoryGB,
    @{n='CpuResMhz';e={$_.ExtensionData.ResourceConfig.CpuAllocation.Reservation}},
    @{n='MemResMB';e={$_.ExtensionData.ResourceConfig.MemoryAllocation.Reservation}} |
  Sort-Object MemResMB -Descending | Select-Object -First 20

"=== Disconnect-VIServer -Confirm:`$false ==="
Disconnect-VIServer -Confirm:$false
```

**Manual items to pair with the script (cannot be scripted from PowerCLI):**

```bash
# Certificate expiry (A1) - run on every vCenter node weekly
for store in $(/usr/lib/vmware-vmafd/bin/vecs-cli store list | grep -v TRUSTED_ROOT_CRLS); do
  echo "[*] Store :" $store
  /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store --text | grep -ie "Alias" -ie "Not After"
done;

# Appliance partitions (A3) and backup success (A5)
df -h; df -i
grep -icE "error|failed" /var/log/vmware/applmgmt/backup.log
```

---

## Appendix D — Monitoring, Alerting & Threshold Catalogue

| # | Signal | Where measured | Warning | Critical | Maps to SOP |
|---|---|---|---|---|---|
| D1 | Certificate `Not After` (all stores, all VC nodes) | VCSA CLI loop / monitoring script | < 60 days | < 30 days | A1 |
| D2 | Any core service not `Running` | `service-control --status --all` | Any `StartPending` > 5 min | Core service `Stopped` | A2 |
| D3 | `/storage/seat` usage | VCSA | > 70 % | > 90 % (95 % = vpxd self-stop) | A3 |
| D4 | `/storage/seat` growth rate | VCSA sampling | > 500 MB/day | > 2 GB/day | A3 |
| D5 | `/storage/log`, `/storage/db`, `/storage/core` usage | VCSA | > 80 % | > 90 % | A3 |
| D6 | Inode usage on any appliance mount | VCSA | > 70 % | > 90 % | A3 |
| D7 | vCenter event rate (events/min) | VCSA / monitoring | > 2× baseline | > 5× baseline | A3 |
| D8 | VCHA cluster state | vSphere alarm | *Degraded* | *Isolated* / *Destroyed* | A4 |
| D9 | VCHA heartbeat RTT between nodes | Network monitoring | > 5 ms | > 10 ms (requirement breach) | A4 |
| D10 | VCHA node placement (hosts/datastores) | vSphere inventory | Shared datastore | Shared host | A4 |
| D11 | File-based backup job result | VAMI / `backup.log` | Completed with warnings | Failed / no successful run in 7 days | A5 |
| D12 | Backup destination free space | Destination host | < 40 % free | < 20 % free (2× rule) | A5 |
| D13 | Restore test age | Records | > 12 months | > 18 months | A5 |
| D14 | VM power-on failures with lock errors | vCenter events | Any occurrence | Repeat within 24 h | B1 |
| D15 | `ConsolidationNeeded` flag | PowerCLI sweep | Any VM | Any VM for > 24 h | B2 |
| D16 | Snapshot age | PowerCLI sweep | > 72 h | > 7 days | B2 |
| D17 | Snapshot count per VM | PowerCLI sweep | > 3 | > 8 (limit 32) | B2 |
| D18 | Delta file growth per VM | Datastore monitoring | > 20 GB/day | > 50 GB/day | B2 |
| D19 | Failed vMotion/DRS migration tasks | vCenter events | Any | > 3 per host per day | B3 |
| D20 | Host patch-level divergence in a cluster | Compliance scan | Any | > 1 minor version / > 3 months apart | B3 |
| D21 | Cluster `CurrentFailoverLevel` vs desired | PowerCLI / API | Desired − 1 | Desired not met / zero | B4 |
| D22 | Admission control disabled | vCenter event | Any occurrence | Any occurrence > 24 h | B4 |
| D23 | VM per-vCPU CPU ready (converted) | vSphere charts / esxtop | > 2 % (latency-sensitive), > 5 % general | > 10 % | B5 |
| D24 | CPU co-stop (`%CSTP`) | esxtop / charts | > 3 % | > 10 % | B5 |
| D25 | CPU max-limited (`%MLMTD`) | esxtop / charts | Any non-zero with slowness report | Sustained non-zero | B5 |
| D26 | Memory balloon / swap on host | esxtop / charts | Any ballooning | Any swap activity | B5 |
| D27 | Datastore latency (`DAVG`/chart latency) | esxtop / vCenter charts | > 20 ms | > 40 ms | B5 |
| D28 | Datastore free space | Any | < 25 % | < 15 % | B2/B5 |
| D29 | APD/PDL events on any host | vmkernel events | Any | Any | B1/B5 |
| D30 | NTP sync/offset | VCSA + hosts | > 1 s offset | Not synced | A1/A2 |

**Alert routing:** D1–D13 → virtualization on-call (vCenter platform queue). D14–D29 → virtualization on-call (workload queue). D30 → both. S1-class alerts must page; S3-class may be ticketed within business hours.

---

## Appendix E — Proactive Maintenance Calendar

| Cadence | Activity | Owner | Evidence of completion | SOP link |
|---|---|---|---|---|
| **Weekly** | Run the Appendix C health sweep; review consolidation, snapshots, datastore headroom | L2 | Saved report + remediation tickets | B2, B4 |
| **Weekly** | Certificate expiry inventory on every vCenter node | L2 | Saved CLI output | A1 |
| **Weekly** | Review failed backups and VAMI job history | Backup Admin | Backup report | A5 |
| **Weekly** | Check appliance partitions (`df -h`, `df -i`) and event-rate trend | L2 | Screenshot/output | A3 |
| **Monthly** | Validate privileged access: root SSH, SSO admin, backup target credentials | L2 | Access test record | §5.1 |
| **Monthly** | VCDB review: table sizes, dead tuples, statistics level, retention settings | L3 | DB review note | A3 |
| **Monthly** | Review HA admission-control headroom and reservations across clusters | L3 | Capacity note | B4 |
| **Quarterly** | Capacity review: CPU/memory headroom, overcommit ratios, ready-time trends | L3 | Capacity plan | B5 |
| **Quarterly** | Test a live vMotion from every host generation pair; confirm EVC behaves as designed | L2 | Migration test log | B3 |
| **Quarterly** | Inventory-wide snapshot/consolidation sweep and cleanup | L2 | Report | B2 |
| **Quarterly** | Verify support bundle generation works and is retrievable | L2 | Bundle test | Appendix B |
| **Semi-annually** | Restore-test a **file-based backup** into an isolated network | Backup Admin + L2 | Restore record with timings | A5 |
| **Semi-annually** | Review snapshot policy compliance per application tier | L2 + App Owner | Policy attestation | B2 |
| **Annually** | **VCHA failover test** (planned failover and fail back) | L3 | Test report with RTO | A4 |
| **Annually** | Certificate renewal **dry run** (including custom-CA re-import) in the lab | L3 | Timed run sheet | A1 |
| **Annually** | Full DR exercise: restore vCenter + a tier-1 VM, validate runbooks | All | DR exercise report | A5, B1 |
| **Annually** | SOP review and re-approval (this document) | Owner + Approver | Signed revision history entry | All |
| **Per change** | Pre-change checks (certificates, storage, snapshots) and post-change health validation | L2 | Change record | §8, A2.7 |
| **Per upgrade** | vCenter patch: backup verification + post-upgrade service/client/VM-operation test | L2 | Upgrade checklist | A2, A5 |

---

## Appendix F — Incident Record & Change Sign-Off Template

### F.1 Incident record (one per event)

```
INCIDENT RECORD                                        Ticket/INC: ______________
------------------------------------------------------------------------------
Detected by / at:            ____________________ / ____________
Reported symptom (verbatim): ______________________________________________
SOP selected (A1-A5/B1-B5):  ______   Justification: ______________________
Severity:                    S1 | S2 | S3 | S4        Bridge call: Y/N
Impact statement:            (business function, # VMs, # users) ____________

--- EVIDENCE (attach outputs) ---
[ ] service-control --status --all      [ ] df -h / df -i
[ ] Certificate inventory loop           [ ] Relevant service logs (paths: ____)
[ ] ESXi host logs (hosts: ________)     [ ] VM vmware.log / chain listing
[ ] Performance charts (window: ______)  [ ] Screenshots of UI errors
Support bundle started at: ______  Completed: Y/N

--- SAFEGUARD ---
Snapshot taken: Y/N  Name: ____________  Time: ______  Removed at: ______
Backup verified (if restore path needed): ___________________________
Change record / CAB approval: ______________________________________

--- ACTIONS (timestamped) ---
HH:MM  Action: ______________________________  Result: ______________
HH:MM  Action: ______________________________  Result: ______________
HH:MM  Action: ______________________________  Result: ______________

--- STOP CONDITIONS ENCOUNTERED? ---
[ ] Datastore metadata / VOMA required   [ ] Chain corruption suspected
[ ] ELM/VCHA structural decision         [ ] DB corruption suspected
Escalated to L3 at ______   Broadcom SR #: ____________

--- VERIFICATION (SOP checklist) ---
All V-checks passed? Y/N   Exceptions: ______________________________

--- RECOVERY CONFIRMED ---
Recovered at: ______   Service restored verified by: __________________
Residual risk / monitoring period: ___________________________________
```

### F.2 Post-incident review (S1/S2 — within 5 business days)

| Question | Answer |
|---|---|
| What was the technical root cause (not the trigger)? | |
| Was the SOP followed? If not, why? | |
| Which SOP step failed, was missing, or was wrong (SOP improvement)? | |
| Was the alerting appropriate (too late / too noisy / missing)? | |
| What monitoring threshold should change (Appendix D)? | |
| What preventive action is required, with owner and due date? | |
| Is this a repeat incident? If yes, why wasn't the prior action effective? | |
| Documentation/CMDB updates required? | |

### F.3 Change sign-off (for Part A procedures)

```
CHANGE RECORD                                          CR/CHG: ______________
SOP + steps applied: ____________________  Window: ____________
Pre-checks complete (certs/space/snapshot/DNS/time):  Y/N   Evidence: ______
Rollback point: ____________________  Rollback plan reviewed by: ____________
Executed by: ____________  Verified by: ____________  Business approval: ______
Post-change validation (services, UI, VAMI, one VM op, backup):  PASS/FAIL
Temporary settings introduced (list) and their reversal date: ______________
```

---

## Appendix G — Glossary

| Term | Meaning |
|---|---|
| **APD / PDL** | All Paths Down / Permanent Device Loss — storage connectivity states that commonly precede lock and consolidation incidents |
| **CBT / CTK** | Changed Block Tracking / change-tracking files used by backup products |
| **ELM** | Enhanced Linked Mode — multiple vCenter nodes sharing one SSO domain |
| **EVC** | Enhanced vMotion Compatibility — a normalized CPU feature baseline for a cluster |
| **FDM** | Fault Domain Manager — the ESXi HA agent (`/var/log/fdm.log`) |
| **VCDB** | vCenter database (vPostgres) hosted on the appliance |
| **VECS** | VMware Endpoint Certificate Store — where vCenter certificates live (`vecs-cli`) |
| **VMCA** | VMware Certificate Authority — issues internal VMCA-signed certificates |
| **VCHA** | vCenter High Availability (Active / Passive / Witness nodes) |
| **VMDIR** | VMware Directory Service (`vmdird`) — the SSO directory backend |
| **vMon / service-control** | The vCenter services framework and its control CLI |
| **STS** | Security Token Service — issues SAML tokens for vCenter authentication |
| **%RDY / %CSTP / %MLMTD** | esxtop CPU metrics: ready time, co-stop, max-limited |
| **DAVG / KAVG / GAVG** | esxtop storage latencies: device, kernel, guest-observed |

---

## Appendix H — Reference Policy & Knowledge-Base Verification

1. **Verify KB numbers before quoting them in a change record or vendor case.** Broadcom migrated the legacy `kb.vmware.com` articles to `knowledge.broadcom.com`; legacy IDs still resolve via the KB portal's search, and article numbers for a given symptom can change when articles are consolidated or rewritten.
2. Each SOP section above carries the KB IDs verified while authoring this document. Where an ID could not be verified at authoring time, the reference is given by **title** with a note to confirm the current number.
3. **Interactive tool menus change between releases.** All `certificate-manager` and `vCert` steps in this SOP are written as **labels first, numbers second** for that reason.
4. **Version applicability:** procedures were authored against vSphere 6.7 U3 / 7.0 U3 / 8.0 U1–U3. Confirm feature names and file paths on your build before executing in production; several paths and service names are release-specific.
5. **Support-gated actions** (any datastore metadata repair, `voma ... advfix`, VMDIR repair with `lsdoctor`, database-level surgery beyond the documented purge scripts) must be performed with Broadcom engagement and a validated restore point.
6. **This SOP is a template.** Adapt thresholds (§Appendix D), tooling paths, and escalation contacts to your environment, then re-approve the document.

---

*End of SOP-VMW-VC-001 — Version 1.0.*
