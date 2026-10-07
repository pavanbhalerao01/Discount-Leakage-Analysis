# Power BI Dashboard Guide
## Discount Leakage Analysis

This file tells you exactly how to build the 3-page dashboard.  
You cannot use a `.pbix` file because the data is yours to load locally.

---

## Step 0: Connect to Data

### Primary route â€“ MySQL (live connection)

1. Open Power BI Desktop â†’ **Get Data** â†’ **MySQL database**
2. If prompted, install **MySQL Connector/NET** (download from mysql.com/downloads/connector/net/)
3. Server: `localhost`, Database: `discount_leakage`, Mode: **Import**
4. Load **only** these 4 tables: `dept_summary`, `commodity_discount`, `segment_summary`, `campaign_lift`
5. Click **Transform Data**, verify column types match below, then **Close & Apply**

### Fallback route â€“ CSV files

1. **Get Data** â†’ **Text/CSV**, load each file from `data/powerbi/`
2. Files: `dept_summary.csv`, `commodity_discount.csv`, `segment_summary.csv`, `campaign_lift.csv`
3. Promote first row as headers if not automatic

### Column types to verify

| Table | Column | Type |
|---|---|---|
| dept_summary | net_sales, gross_sales, retailer_disc, mfr_disc | Decimal Number |
| dept_summary | retailer_disc_rate_pct, pct_of_all_retailer_disc | Decimal Number |
| commodity_discount | retailer_disc, gross_sales | Decimal Number |
| commodity_discount | disc_rate_pct, share_of_disc_pct, share_of_sales_pct, cum_share_of_disc_pct | Decimal Number |
| commodity_discount | rnk | Whole Number |
| campaign_lift | lift_usd_per_hh, mailed_pre, mailed_during, other_pre, other_during | Decimal Number |
| campaign_lift | mailed_change_pct, other_change_pct | Decimal Number |

---

## Step 1: Create All DAX Measures

Go to **Modeling** tab â†’ **New Measure** for each one below.  
Put all measures in the `dept_summary` table to keep things tidy.

```dax
Net Sales = SUM(dept_summary[net_sales])

Gross Sales = SUM(dept_summary[gross_sales])

Retailer Discount = SUM(dept_summary[retailer_disc])

Manufacturer Discount = SUM(dept_summary[mfr_disc])

Retailer Discount Rate = DIVIDE([Retailer Discount], [Gross Sales])

Manufacturer Share = DIVIDE([Manufacturer Discount], [Retailer Discount] + [Manufacturer Discount])

Avg Lift per Household = AVERAGE(campaign_lift[lift_usd_per_hh])
```

### What-if parameter (Margin slider)

1. **Modeling** â†’ **New Parameter**
2. Name: `Margin`, Type: Decimal, Min: `0.10`, Max: `0.40`, Step: `0.01`, Default: `0.25`
3. Power BI creates a `Margin` table and this measure automatically:

```dax
Margin Value = SELECTEDVALUE(Margin[Margin], 0.25)
```

4. Add the break-even measure manually:

```dax
Break-even Uplift % =
IF(
    [Retailer Discount Rate] < [Margin Value],
    DIVIDE(
        [Retailer Discount Rate],
        [Margin Value] - [Retailer Discount Rate]
    ),
    BLANK()
)
```

**How break-even works (2-line explanation):**  
The formula is `d / (m - d)`, derived from `m / (m - d) - 1 = 0` (the uplift at which incremental gross profit equals the discount cost).  
It returns BLANK when `d >= m` because in that case the department already gives away more than its entire margin â€” no amount of volume uplift can break even.

---

## Step 2: Build Page 1 â€“ "Discount Overview"

**Page name:** `Discount Overview`

### Cards row (5 cards across the top)

| Card # | Field / Measure | Label |
|---|---|---|
| 1 | `[Net Sales]` | Net Sales |
| 2 | `[Gross Sales]` | Gross Sales (pre-discount) |
| 3 | `[Retailer Discount]` | Retailer Discount |
| 4 | `[Retailer Discount Rate]` | Retailer Disc Rate â€” format as % |
| 5 | `[Manufacturer Share]` | Manufacturer Share â€” format as % |

### Chart 1: Retailer discount rate by department (bar chart)

- Visual: **Clustered Bar Chart**
- Y-axis: `dept_summary[department]`
- X-axis: `dept_summary[retailer_disc_rate_pct]`
- Sort: descending by rate
- Title: "Retailer Discount Rate % by Department"
- Data label: on, format `0.0%` â€” note the column is already in percent so format as plain number with one decimal

### Chart 2: Retailer vs manufacturer discount by department (stacked bar)

- Visual: **Stacked Bar Chart**
- Y-axis: `dept_summary[department]`
- X-axis Values: `dept_summary[retailer_disc]` (series 1), `dept_summary[mfr_disc]` (series 2)
- Legend labels: "Retailer Funded", "Manufacturer Funded"
- Sort: descending by total discount
- Title: "Retailer vs Manufacturer Discount by Department ($)"

---

## Step 3: Build Page 2 â€“ "Where the Money Goes"

**Page name:** `Where the Money Goes`

### Chart 1: Commodity Pareto (top 20) â€” combo chart

- Visual: **Line and Clustered Column Chart**
- Filter: add a visual-level filter on `commodity_discount[rnk]` â†’ **is less than or equal to** `20`
- X-axis: `commodity_discount[commodity_desc]`
- Column values: `commodity_discount[retailer_disc]`
- Line values: `commodity_discount[cum_share_of_disc_pct]`
- Sort X-axis: ascending by `rnk`
- Secondary Y-axis: on (for the cumulative % line), format as number (the column is already 0â€“100)
- Title: "Top 20 Commodities â€“ Retailer Discount & Cumulative Share"
- Add a reference line on the secondary axis at **80** (80% of discounts) if your Power BI version supports it

### Chart 2: Commodity detail table

- Visual: **Table**
- Columns (in order): `commodity_desc`, `department`, `retailer_disc`, `disc_rate_pct`, `share_of_disc_pct`, `share_of_sales_pct`
- Conditional formatting on `disc_rate_pct`: background color scale (white â†’ red)
- Filter: `rnk <= 20`
- Title: "Top 20 Commodity Detail"

### Chart 3: Spend share vs discount share by segment (clustered bar)

- Visual: **Clustered Bar Chart**
- Y-axis: `segment_summary[segment]`
- X-axis Values: `pct_of_net_sales`, `pct_of_retailer_disc`
- Add a **slicer** on `segment_summary[segment_type]` so users can toggle between "Spend quartile" and "Deal group"
- Title: "% of Net Sales vs % of Retailer Discount by Household Segment"
- Goal: columns of equal height = proportional; discount bar taller = that segment gets a disproportionate share

---

## Step 4: Build Page 3 â€“ "Campaigns & Break-even"

**Page name:** `Campaigns & Break-even`

### Chart 1: Average lift per household by campaign type (bar chart)

- Visual: **Clustered Bar Chart**
- Y-axis: `campaign_lift[campaign_type]`
- X-axis: `[Avg Lift per Household]`
- Sort: descending by lift
- Reference line at X = 0 (zero lift threshold)
- Title: "Avg Incremental Spend per Household by Campaign Type ($)"

### Chart 2: Pre-campaign spend comparison (table)

- Visual: **Table**
- Source: `campaign_lift`
- Columns: `campaign`, `campaign_type`, `mailed_hh`, `other_hh`, `mailed_pre`, `other_pre`, `mailed_during`, `other_during`, `lift_usd_per_hh`
- Conditional formatting on `mailed_pre` vs `other_pre`: if mailed_pre > other_pre for most rows, mailed households were already higher spenders â†’ selection bias
- Title: "Campaign Detail: Mailed vs Not-Mailed Spend"

### Chart 3: Break-even uplift % by department (table with slider)

- Add the **Margin** parameter slicer to this page (drag `Margin[Margin]` onto the canvas, choose Slicer visual)
- Visual: **Table**
- Source: `dept_summary`
- Columns: `department`, `retailer_disc_rate_pct`, `pct_of_all_retailer_disc`, `[Break-even Uplift %]`
- Format `[Break-even Uplift %]` as percentage
- Title: "Break-even Uplift Required by Department (drag Margin slider)"

### Text box (important caveat)

Add a text box to this page with the following text:

> **Caveat:** Margin is an assumption â€” the dataset has no cost data. Break-even uplift is a scenario tool, not a fact. Campaign lift is an association between mailing and spend change; mailed households were not randomly assigned. Use these numbers to frame hypotheses, not to make final decisions.

---

## Step 5: Final Polish

- Set **canvas size** to 16:9 (1280 Ã— 720) for all pages
- Add a consistent **page header** text box to each page with the project title and page name
- Choose a single **theme** (Power BI Desktop â†’ View â†’ Themes â€” "Executive" or a dark custom theme works well)
- Save the file as `discount_leakage.pbix` in the project root (do not commit if file is large)
- Export screenshots of each page to `images/` once complete

---

## Export Summary Tables for data/powerbi/

In MySQL Workbench:
1. Run `SELECT * FROM dept_summary;` â†’ right-click result grid â†’ **Export** â†’ CSV
2. Repeat for `commodity_discount`, `segment_summary`, `campaign_lift`
3. Save files to `data/powerbi/` with matching names
4. These files are small enough to commit to the repository

