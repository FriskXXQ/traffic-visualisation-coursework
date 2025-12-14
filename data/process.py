import os
import re
import pandas as pd

# ========= 0) Ensure that the relative path is available =========
os.chdir(os.path.dirname(__file__))

INPUT = "cordon.csv"
OUTPUT = "cordon_processed.csv"

# ========= 1) read data =========
df = pd.read_csv(INPUT, low_memory=False)

# ========= 2) ）Generate site_id (extracted from SiteNumber - e.g. -001) as a three-digit code =========
# SiteNumber eg：3424-IRE-Nov2019-023-VEHOCC
df["site_id"] = df["SiteNumber"].str.extract(r"-(\d{3})-")[0]
df = df.dropna(subset=["site_id"])
df["site_id"] = df["site_id"].astype(int)

#  Only retain the parts on the map 1~33
df = df[(df["site_id"] >= 1) & (df["site_id"] <= 33)]

# ========= 3) Timeline: Define 48 points from 07:00 to 18:45 and generate the 'time_index' =========
df["Time"] = df["Time"].astype(str).str.slice(0, 5)  # "07:00:00" -> "07:00"
time_labels = pd.date_range("07:00", "18:45", freq="15min").strftime("%H:%M").tolist()
time_to_index = {t: i for i, t in enumerate(time_labels)}

# Only retain the data within this time frame.
df = df[df["Time"].isin(time_to_index)]
df["time_index"] = df["Time"].map(time_to_index).astype(int)

# ========= 4)  Decide "which counting systems to use" =========
# Vehicle flow should only use JTC + LINK (both of which refer to "vehicles")
# ignore PEDX
df = df[df["CountGroup"].isin(["JTC", "LINK"])]

# ========= 5) Classification of vehicle types：CountType -> vehicle_group =========
def to_vehicle_group(ct: str):
    ct = str(ct).strip().upper()
    ct_nospace = re.sub(r"\s+", "", ct)  # delete space

    # Exclude these "non-vehicle type counts" (otherwise, there would be duplicate counting or semantic confusion)
    if ct_nospace in ["VEHTOTAL", "PCU", "P/C", "M/C", "PED"] or ct.startswith("CAROCC"):
        return None

    if ct_nospace in ["CAR", "TAXI"]:
        return "CAR"
    if ct_nospace in ["DBUS", "OBUS"]:
        return "BUS"
    # LGV + all HGV* be HGV
    if ct_nospace == "LGV" or ct_nospace.startswith("HGV"):
        return "HGV"

    return None

df["vehicle_group"] = df["CountType"].apply(to_vehicle_group)
df = df.dropna(subset=["vehicle_group"])

# ========= 6) Aggregation: Summarize "event-level records" into (site_id, time_index, vehicle_group)->count =========
g = (
    df.groupby(["site_id", "time_index", "vehicle_group"], as_index=False)["CountValue"]
      .sum()
      .rename(columns={"CountValue": "count"})
)

# ========= 7)generate ALL =========
all_g = (
    g.groupby(["site_id", "time_index"], as_index=False)["count"]
     .sum()
)
all_g["vehicle_group"] = "ALL"

final_df = pd.concat([g, all_g], ignore_index=True)

# ========= 8) Complete the missing combinations (very important: ensure that Processing does not lack indices) =========
vehicle_groups = ["ALL", "CAR", "BUS", "HGV"]
full_index = pd.MultiIndex.from_product(
    [range(1, 34), range(0, 48), vehicle_groups],
    names=["site_id", "time_index", "vehicle_group"]
)

final_df = (
    final_df.set_index(["site_id", "time_index", "vehicle_group"])
            .reindex(full_index, fill_value=0)
            .reset_index()
)

# ========= 9) add time_label + order =========
final_df["time_label"] = final_df["time_index"].apply(lambda i: time_labels[i])
final_df = final_df.sort_values(["site_id", "time_index", "vehicle_group"])

# ========= 10) output =========
final_df.to_csv(OUTPUT, index=False, encoding="utf-8-sig")

print(f"Done. Wrote {OUTPUT}")
print(final_df.head(12))