#!/usr/bin/env python3
"""
Load test for the JOLAY backend (stdlib only). Seeds drivers/customers directly in PostgreSQL, mints access tokens with the
configured JWT secret, then measures: (A) driver location updates, (B) concurrent ride requests incl. immediate dispatch,
(C) concurrent offer acceptance, (D) customer ride polling.

  JOLAY_JWT_SECRET=... python3 scripts/loadtest.py --drivers 300 --customers 150
Requires: psql on PATH with access to the target DB (PGPASSWORD etc.) and a running backend.
"""
import argparse, base64, hashlib, hmac, http.client, json, os, random, statistics, subprocess, threading, time, uuid
from concurrent.futures import ThreadPoolExecutor

ap = argparse.ArgumentParser()
ap.add_argument("--host", default="localhost"); ap.add_argument("--port", type=int, default=8080)
ap.add_argument("--drivers", type=int, default=300); ap.add_argument("--customers", type=int, default=150)
ap.add_argument("--threads", type=int, default=32); ap.add_argument("--seconds", type=int, default=20)
ap.add_argument("--db", default="jolay"); ap.add_argument("--dbuser", default="jolay")
a = ap.parse_args()
SECRET = os.environ.get("JOLAY_JWT_SECRET", "dev-only-secret-change-me-dev-only-secret-change-me").encode()
os.environ.setdefault("PGPASSWORD", "jolay")

def psql(sql):
    r = subprocess.run(["psql", "-h", "localhost", "-U", a.dbuser, "-d", a.db, "-q", "-t", "-A", "-c", sql], capture_output=True, text=True)
    if r.returncode: raise SystemExit(r.stderr)
    return r.stdout

def b64(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
def token(uid, roles):
    h = b64(json.dumps({"alg": "HS256"}).encode()); now = int(time.time())
    p = b64(json.dumps({"sub": uid, "roles": roles, "iat": now, "exp": now + 3600}).encode())
    s = b64(hmac.new(SECRET, f"{h}.{p}".encode(), hashlib.sha256).digest())
    return f"{h}.{p}.{s}"

# ---------- seed ----------
random.seed(7)
psql("TRUNCATE users RESTART IDENTITY CASCADE; INSERT INTO accounts(type) VALUES ('PLATFORM_REVENUE'),('EXTERNAL_CARD'),('EXTERNAL_CASH'),('PROMO') ON CONFLICT DO NOTHING;")
city = psql("SELECT id FROM cities WHERE code='ALA'").strip()
drivers = [str(uuid.uuid4()) for _ in range(a.drivers)]
customers = [str(uuid.uuid4()) for _ in range(a.customers)]
rows = []
for i, d in enumerate(drivers): rows.append(f"('{d}','+7700{i:07d}','x','Driver {i}',true)")
for i, c in enumerate(customers): rows.append(f"('{c}','+7701{i:07d}','x','Customer {i}',true)")
psql("INSERT INTO users(id,phone,password_hash,full_name,phone_verified) VALUES " + ",".join(rows))
psql("INSERT INTO user_roles SELECT id,'DRIVER' FROM users WHERE phone LIKE '+7700%'; INSERT INTO user_roles SELECT id,'CUSTOMER' FROM users WHERE phone LIKE '+7701%'")
psql(f"INSERT INTO drivers(user_id,city_id,verification,availability) SELECT id,'{city}','APPROVED','ONLINE' FROM users WHERE phone LIKE '+7700%'")
psql("INSERT INTO vehicles(driver_id,brand,model,year,color,plate,category_code,approved) SELECT id,'Toyota','Camry',2020,'White','L'||substr(replace(id::text,'-',''),1,10),'ECONOMY',true FROM users WHERE phone LIKE '+7700%'")
CLAT, CLNG = 43.2389, 76.8897
def rnd_pt(r_deg=0.04): return CLAT + random.uniform(-r_deg, r_deg), CLNG + random.uniform(-r_deg, r_deg)
locs = {d: rnd_pt() for d in drivers}
psql("INSERT INTO driver_locations(driver_id,location) VALUES " + ",".join(f"('{d}',ST_SetSRID(ST_MakePoint({lng},{lat}),4326)::geography)" for d, (lat, lng) in locs.items()))
dtok = {d: token(d, ["DRIVER"]) for d in drivers}; ctok = {c: token(c, ["CUSTOMER"]) for c in customers}

# ---------- http ----------
tl = threading.local()
def req(method, path, tok, body=None):
    c = getattr(tl, "c", None)
    if c is None: c = tl.c = http.client.HTTPConnection(a.host, a.port, timeout=30)
    t0 = time.perf_counter()
    try:
        c.request(method, path, json.dumps(body) if body is not None else None, {"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
        r = c.getresponse(); data = r.read(); st = r.status
    except Exception:
        tl.c = None; return 0, None, time.perf_counter() - t0
    return st, (json.loads(data) if data else None), time.perf_counter() - t0

def pct(l, p): l = sorted(l); return l[min(len(l) - 1, int(len(l) * p))] * 1000 if l else float("nan")
def report(name, lat, statuses, wall):
    ok = sum(1 for s in statuses if 200 <= s < 300)
    print(f"{name:34s} n={len(lat):6d} ok={ok:6d} rps={len(lat)/wall:8.1f} p50={pct(lat,.5):7.1f}ms p95={pct(lat,.95):7.1f}ms p99={pct(lat,.99):7.1f}ms max={max(lat)*1000 if lat else 0:7.1f}ms")
    codes = {}
    for s in statuses: codes[s] = codes.get(s, 0) + 1
    if len(codes) > 1 or ok != len(statuses): print("   status codes:", codes)

# ---------- A: location updates ----------
def loc_worker(stop, out):
    while time.time() < stop:
        d = random.choice(drivers); la, ln = locs[d]
        la += random.uniform(-.0002, .0002); ln += random.uniform(-.0002, .0002); locs[d] = (la, ln)   # ~20 m steps, plausible speed
        st, _, dt = req("POST", "/api/v1/drivers/location", dtok[d], {"point": {"lat": la, "lng": ln}, "heading": 90, "speedKmh": 30}); out.append((st, dt))
out = []; stop = time.time() + a.seconds; t0 = time.time()
with ThreadPoolExecutor(a.threads) as ex:
    for _ in range(a.threads): ex.submit(loc_worker, stop, out)
report("A location updates", [x[1] for x in out], [x[0] for x in out], time.time() - t0)

# ---------- B: concurrent ride requests (includes first dispatch round) ----------
def ride(c):
    la, ln = rnd_pt(0.03); la2, ln2 = rnd_pt(0.03)
    return req("POST", "/api/v1/rides", ctok[c], {"pickup": {"point": {"lat": la, "lng": ln}, "address": "A"}, "dropoff": {"point": {"lat": la2, "lng": ln2}, "address": "B"}, "category": "ECONOMY", "paymentMethod": "CASH"})
t0 = time.time()
with ThreadPoolExecutor(a.threads) as ex: res = list(ex.map(ride, customers))
report("B ride requests (+dispatch)", [r[2] for r in res], [r[0] for r in res], time.time() - t0)
time.sleep(3)
offers = int(psql("SELECT count(*) FROM ride_offers WHERE status='OFFERED'"))
dup = int(psql("SELECT count(*) FROM (SELECT driver_id FROM ride_offers WHERE status='OFFERED' GROUP BY 1 HAVING count(*)>1) x"))
searching = psql("SELECT count(*) FROM rides WHERE status='SEARCHING_DRIVER'").strip()
print(f"   rides searching={searching} active offers={offers} drivers holding >1 offer={dup}")

# ---------- C: concurrent accepts ----------
offer_rows = [l.split("|") for l in psql("SELECT id, driver_id FROM ride_offers WHERE status='OFFERED'").strip().splitlines()]
def accept(o): return req("POST", f"/api/v1/drivers/offers/{o[0]}/accept", dtok[o[1]])
t0 = time.time()
with ThreadPoolExecutor(a.threads) as ex: res = list(ex.map(accept, offer_rows))
report("C offer accept", [r[2] for r in res], [r[0] for r in res], time.time() - t0)
assigned = int(psql("SELECT count(*) FROM rides WHERE status='DRIVER_ASSIGNED'"))
conflicts = int(psql("SELECT count(*) FROM (SELECT driver_id FROM rides WHERE driver_id IS NOT NULL AND status IN ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS') GROUP BY 1 HAVING count(*)>1) x"))
print(f"   assigned rides={assigned} drivers with >1 active ride={conflicts}")

# ---------- D: polling reads ----------
def poll(c): return req("GET", "/api/v1/rides/active", ctok[c])
t0 = time.time(); allr = []
with ThreadPoolExecutor(a.threads) as ex:
    for _ in range(5): allr += list(ex.map(poll, customers))
report("D GET /rides/active", [r[2] for r in allr], [r[0] for r in allr], time.time() - t0)
print("ledger sum (must be 0):", psql("SELECT COALESCE(sum(balance),0) FROM accounts").strip())
