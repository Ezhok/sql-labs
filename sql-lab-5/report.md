# Lab 5: Subqueries and Analytical Queries — Team B (Variant 2)

## Executive Summary

This report presents the findings of Lab 5 ("Advanced SQL: Subqueries") for the **"Pitanie+"** manufacturing and supply chain database. Operating under **Team B (Variant 2: Production and Procurement)**, we performed a deep-dive data audit to uncover procurement inefficiencies, financial overpayments, supplier reliability risks, production shift anomalies, and material write-off patterns.

## 1. Key Audit Findings & Analytical Results

### Task B-1 & B-2: Procurement Overpayment Analysis

* **Primary Offender:** ООО "АгроСнаб-М" is identified as the single largest source of financial overpayments, accounting for **3,935,228.40 RUB** in excess spending.

* **Responsible Purchasing Agents:** Orders placed with ООО "АгроСнаб-М" are heavily concentrated among two agents: **Сидорова Юлия Олеговна** (84 orders) and **Карпов Роман Евгеньевич** (19 orders). This points to either poor vendor management or localized non-competitive purchasing behavior.

* **Price Variance:** When evaluated against quarterly baseline averages, ООО "АгроСнаб-М" consistently supplies key ingredients (sugar, cocoa powder, glucose syrup, vegetable oil) at prices exceeding market thresholds by over 10%.

### Task B-3: Supplier Benchmarking (`NOT EXISTS`)

* **Reliability Screening:** Out of all active suppliers, only **ООО "Кубань-Сахар"** maintains a flawless record with zero rejected or partially accepted deliveries.

* **Price Benchmark Comparison:** A direct comparison on sugar (`material_id = 4`) highlights a dramatic cost disparity:

  * **ООО "Кубань-Сахар" (Ideal):** Weighted price of **63.85 RUB/kg** across 22 deliveries.

  * **ООО "АгроСнаб-М" (Inefficient):** Weighted price of **80.52 RUB/kg** across 60 deliveries (a **26% markup**).

### Task B-4: Production Defect Anomalies by Shift

* **Line 3 Critical Shift Anomaly:** On **Line 3 (Dairy Production)**, **100% of batches** exceeding the line's average defect rate occur exclusively during the **night shift** (627 batches), with zero high-defect batches recorded during the day shift. This indicates critical procedural breakdowns, lack of supervision, or equipment calibration drift during overnight hours.

### Task B-5: Purchased vs. Written-Off Materials

* Exactly **20 materials** are confirmed to be both purchased and written off.

* **Top Write-Off Loss:** *Наполнитель клубничный* (`material_id = 10`) leads all losses with **1,151,630.53 RUB** written off, driven by short shelf life (90 days) and poor inventory turnover relative to purchasing volumes.

### Task B-6: Raw Material Overconsumption

* Applying a >2% consumption threshold reveals three critical materials exceeding normative recipes:

  1. **Какао-масло:** +12.52% overconsumption ($\approx 5.51$M RUB loss).

  2. **Какао-порошок:** +11.28% overconsumption ($\approx 2.35$M RUB loss).

  3. **Молоко сырое:** +2.13% overconsumption ($\approx 1.89$M RUB loss).

## 2. Recommendations for Management

1. **Vendor Replacement:** Immediately freeze procurement contracts with ООО "АгроСнаб-М" and redirect sugar and bulk material procurement toward ООО "Кубань-Сахар" and other verified benchmark vendors.

2. **Internal Audit of Purchasing Agents:** Conduct an internal review of procurement practices by Сидорова Ю.О. and Карпов Р.Е.

3. **Night Shift Intervention on Line 3:** Deploy quality control engineers and automated monitoring to Line 3 night shifts to mitigate the 100% defect concentration.

4. **Inventory & Recipe Control:** Establish stricter safety-stock rules for short shelf-life items (e.g., strawberry filling) and investigate the root cause of cocoa butter and powder overconsumption in confectionery lines.