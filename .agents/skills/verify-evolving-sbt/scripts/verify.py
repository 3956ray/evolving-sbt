#!/usr/bin/env python3
"""Local-only public-ABI verification with durable evidence and owned-process cleanup."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from urllib.request import Request, build_opener, ProxyHandler

ROOT = Path(__file__).resolve().parents[4]
MATCHES = {
    "qualification": "test(Fuzz)?Qualification",
    "initialization": "test(RelayedInitialize|HolderCanDirectlyConsent|IssuerCannotInitialize|NamespaceRegistration)",
    "growth": "test(AppendChanges|Correction|Duplicate|RecordCap|StateRoots|RejectedCorrection|FuzzCorrection)",
    "validity": "test(Expiry|UseControls|PolicyControls|SuspendResume|Revocation|AppendCannotResume)",
    "authorization": "test(ExactSame|OnlyOneCompeting|WrongPredecessor|PauseResume|ChainDomain|ContractDomain|SignatureBinds|EvidenceCannot|ArbitraryRoot|ERC1271)",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--feature", choices=["lifecycle", *MATCHES], default="lifecycle")
    parser.add_argument("--evidence", type=Path, help="New directory outside disposable scratch")
    args = parser.parse_args()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    evidence = (args.evidence or ROOT.parent / "verification-evidence" / (stamp + "-" + args.feature)).resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    scratch = Path(tempfile.mkdtemp(prefix="evolving-sbt-verify-"))
    env = dict(os.environ)
    for key in list(env):
        if key.startswith(("FOUNDRY_", "DAPP_", "ETH_")):
            env.pop(key)
    env.update(FOUNDRY_OUT=str(scratch / "out"), FOUNDRY_CACHE_PATH=str(scratch / "cache"), FOUNDRY_PROFILE="default")
    report = {"feature": args.feature, "started_utc": stamp, "mode": "local-rpc" if args.feature == "lifecycle" else "foundry-simulation", "status": "failed", "checks": [], "scratch": str(scratch)}
    process = None
    rpc_url = None
    log = None

    def record(kind, data):
        with (evidence / "actions.jsonl").open("a") as f:
            f.write(json.dumps({"time": datetime.now(timezone.utc).isoformat(), "kind": kind, **data}) + "\n")

    def command(*argv):
        p = subprocess.run(argv, cwd=ROOT, env=env, text=True, capture_output=True, timeout=180)
        record("command", {"argv": argv, "exit_code": p.returncode, "stdout": p.stdout, "stderr": p.stderr})
        if p.returncode:
            raise RuntimeError(f"Command failed ({p.returncode}): {argv[0:3]}")
        return p.stdout.strip()

    opener = build_opener(ProxyHandler({}))

    def rpc(method, params):
        request = Request(rpc_url, data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(), headers={"Content-Type": "application/json"})
        with opener.open(request, timeout=5) as response:
            body = json.load(response)
        record("rpc", {"method": method, "params": params, "response": body})
        return body

    def check(name, condition):
        report["checks"].append({"name": name, "passed": bool(condition)})
        if not condition:
            raise AssertionError(name)

    def doctor():
        check("owned anvil process alive", process.poll() is None)
        check("local chain 31337", rpc("eth_chainId", [])["result"] == "0x7a69")
        check("Anvil client", "anvil" in rpc("web3_clientVersion", [])["result"].lower())

    def receipt(txhash):
        for _ in range(40):
            result = rpc("eth_getTransactionReceipt", [txhash]).get("result")
            if result:
                return result
            time.sleep(0.1)
        raise RuntimeError("Receipt timeout")

    def interrupted(signum, frame):
        raise KeyboardInterrupt(f"signal {signum}")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        report["commit"] = command("git", "rev-parse", "HEAD")
        report["git_status_before"] = command("git", "status", "--short")
        report["source_sha256"] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT / "src").rglob("*.sol"))}
        report["harness_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        report["test_sha256"] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT / "test").rglob("*.sol"))}
        report["versions"] = {tool: command(tool, "--version") for tool in ("forge", "cast", "anvil")}
        report["submodules"] = command("git", "submodule", "status")
        command("forge", "build")
        if args.feature != "lifecycle":
            manifest_path = Path(__file__).with_name("required-tests.json")
            manifest = json.loads(manifest_path.read_text())
            expected = manifest[args.feature]
            required = set(expected["required_tests"])
            check("nonempty required test manifest", bool(required))
            report["required_tests_sha256"] = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
            output = command("forge", "test", "--match-contract", "^" + expected["contract"] + "$",
                             "--match-test", MATCHES[args.feature], "-vvvv", "--json")
            result = json.loads(output)
            suite = result.get(expected["suite"], {})
            tests = suite.get("test_results", {})
            passed = {name.split("(", 1)[0] for name, detail in tests.items()
                      if detail.get("status") == "Success"}
            report["required_tests"] = sorted(required)
            report["passed_tests"] = sorted(passed)
            report["missing_tests"] = sorted(required - passed)
            check("selected tests executed without failure or skip", bool(tests) and all(
                detail.get("status") == "Success" for detail in tests.values()))
            check("all required acceptance tests passed", not report["missing_tests"])
        else:
            with socket.socket() as s:
                s.bind(("127.0.0.1", 0))
                port = s.getsockname()[1]
            rpc_url = f"http://127.0.0.1:{port}"
            log = (evidence / "anvil.log").open("w")
            argv = ["anvil", "--host", "127.0.0.1", "--port", str(port), "--chain-id", "31337", "--silent"]
            process = subprocess.Popen(argv, cwd=scratch, env=env, stdout=log, stderr=subprocess.STDOUT)
            report.update(rpc_url=rpc_url, pid=process.pid)
            record("launch", {"argv": argv, "pid": process.pid})
            for _ in range(60):
                if process.poll() is not None:
                    raise RuntimeError("Anvil exited before readiness")
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                        break
                except OSError:
                    time.sleep(0.1)
            doctor()
            check("fresh chain", rpc("eth_blockNumber", [])["result"] == "0x0")
            accounts = rpc("eth_accounts", [])["result"]
            admin, holder, other = accounts[:3]
            for account in (admin, holder, other):
                check("funded local actor", int(rpc("eth_getBalance", [account, "latest"])["result"], 16) > 0)
            deployed = json.loads(command("forge", "create", "src/EvolvingSBT.sol:EvolvingSBT", "--rpc-url", rpc_url, "--unlocked", "--from", admin, "--broadcast", "--json", "--constructor-args", admin))
            contract = deployed["deployedTo"]
            report["contract"] = contract
            check("deployment mined", receipt(deployed["transactionHash"])["status"] == "0x1")
            check("contract has bytecode", rpc("eth_getCode", [contract, "latest"])["result"] != "0x")

            def call(signature, *values, sender=holder):
                data = command("cast", "calldata", signature, *values)
                return rpc("eth_call", [{"from": sender, "to": contract, "data": data}, "latest"])

            def send(signature, *values, sender=holder, succeeds=True):
                data = command("cast", "calldata", signature, *values)
                body = rpc("eth_sendTransaction", [{"from": sender, "to": contract, "data": data, "gas": "0x100000"}])
                if "error" in body:
                    raise RuntimeError(str(body["error"]))
                result = receipt(body["result"])
                check(signature + " receipt", result["status"] == ("0x1" if succeeds else "0x0"))
                return result

            minted = send("mint()")
            topics = [item["topics"][0] for item in minted["logs"]]
            check("Transfer and Locked emitted", all(command("cast", "keccak", sig) in topics for sig in ("Transfer(address,address,uint256)", "Locked(uint256)")))
            check("holder owns token 1", call("ownerOf(uint256)", "1")["result"].lower().endswith(holder[2:].lower()))
            check("token is locked", int(call("locked(uint256)", "1")["result"], 16) == 1)
            check("holder balance is one", int(call("balanceOf(address)", holder)["result"], 16) == 1)
            selector = command("cast", "sig", "Soulbound()")
            for signature, values in [
                ("transferFrom(address,address,uint256)", [holder, other, "1"]),
                ("transferFrom(address,address,uint256)", [holder, holder, "1"]),
                ("safeTransferFrom(address,address,uint256)", [holder, other, "1"]),
                ("safeTransferFrom(address,address,uint256,bytes)", [holder, other, "1", "0x1234"]),
            ]:
                result = call(signature, *values)
                check(signature + " rejects with Soulbound", selector in json.dumps(result.get("error", {})))
                doctor()
            send("transferFrom(address,address,uint256)", holder, other, "1", succeeds=False)
            doctor()
            check("failed transfer preserved holder", call("ownerOf(uint256)", "1")["result"].lower().endswith(holder[2:].lower()))
            send("burn(uint256)", "1", sender=other, succeeds=False)
            doctor()
            check("unauthorized burn preserved token", "result" in call("ownerOf(uint256)", "1"))
            send("burn(uint256)", "1")
            check("burned owner query reverts", "error" in call("ownerOf(uint256)", "1"))
            check("burned lock query reverts", "error" in call("locked(uint256)", "1"))
            check("burn resets holder balance", int(call("balanceOf(address)", holder)["result"], 16) == 0)
            doctor()
            send("mint()")
            check("next token is 2", call("ownerOf(uint256)", "2")["result"].lower().endswith(holder[2:].lower()))
            check("token 1 not reused", "error" in call("ownerOf(uint256)", "1"))
        report["status"] = "passed"
    except BaseException as exc:
        report["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        if process is not None:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            report["process_stopped"] = process.poll() is not None
        if log:
            log.close()
        shutil.rmtree(scratch)
        report["scratch_removed"] = not scratch.exists()
        if rpc_url:
            with socket.socket() as s:
                report["port_closed"] = s.connect_ex(("127.0.0.1", port)) != 0
            if not report["port_closed"]:
                report["status"] = "failed"
        report["evidence_survived_cleanup"] = (evidence / "actions.jsonl").is_file() and (evidence / "actions.jsonl").stat().st_size > 0
        report["finished_utc"] = datetime.now(timezone.utc).isoformat()
        (evidence / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        checksums = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in evidence.iterdir() if p.is_file()}
        (evidence / "sha256.json").write_text(json.dumps(checksums, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "evidence": str(evidence), "error": report.get("error")}, indent=2))
    return 0 if report["status"] == "passed" and report["evidence_survived_cleanup"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
