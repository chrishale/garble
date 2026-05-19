# Level Analytics Guide

This guide explains how to use PostHog and Firebase Analytics to calculate level difficulty and identify the best levels from your test pool.

## Events Captured

| Event | When Fired | Key Properties |
|-------|------------|----------------|
| `test_session_start` | User enters test mode | `session_id` |
| `test_level_start` | Level begins | `level_number`, `garble`, `max_score`, `word_count`, `garble_length` |
| `test_level_complete` | Max score reached | `final_score`, `max_score`, `duration_ms`, `pop_count`, `word_count`, `route` |
| `test_level_skip` | User skips (button or game over) | `current_score`, `max_score`, `pops_used`, `duration_ms` |
| `test_level_abandoned` | User exits test mode mid-puzzle | `current_score`, `max_score`, `pops_used`, `duration_ms`, `score_percentage` |
| `test_level_feedback` | User submits emoji | `emoji`, `was_skipped`, `final_score`, `score_percentage` |
| `test_pop` | Each letter popped | `position`, `formed_word`, `banked_word`, `timestamp_ms` |

---

## Key Metrics for Difficulty

### 1. Completion Rate
Percentage of attempts that reach max score.
- **Easy levels**: > 70% completion rate
- **Medium levels**: 30-70% completion rate
- **Hard levels**: < 30% completion rate

### 2. Skip Rate
Percentage of attempts where user skipped.
- High skip rate (> 50%) suggests level is frustrating or too hard

### 2b. Abandonment Rate
Percentage of attempts where user exited test mode entirely.
- High abandonment (> 20%) on a specific level may indicate a deal-breaker puzzle
- Compare against skip rate: high abandon + low skip = users quit rather than skip

### 3. Average Score Percentage
Mean of `score_percentage` across all attempts.
- Indicates how close players get to max score on average

### 4. Time to Complete
Average `duration_ms` for completed levels.
- Longer times may indicate higher difficulty or engagement

### 5. Feedback Sentiment
Distribution of emoji feedback.
- `thumbs_up` + `happy` = Positive
- `thumbs_down` + `angry` = Negative

---

## PostHog Analysis

### Initial Setup

1. **Log in to PostHog** at [eu.posthog.com](https://eu.posthog.com) (or us.posthog.com)
2. **Select your project** from the dropdown in the top-left
3. **Verify events are arriving**: Click **Activity** in the left sidebar to see recent events

### Navigating the Insights UI

PostHog has several insight types accessible from **Product Analytics → Insights**:

| Type | Best For | Icon |
|------|----------|------|
| **Trends** | Counting events over time, averages, formulas | 📈 |
| **Funnels** | Conversion rates between steps | 🔺 |
| **Retention** | How often users return | 📊 |
| **SQL** | Complex queries, joins, custom calculations | 💻 |

### Creating Your First Insight

1. Click **Product Analytics** in the left sidebar
2. Click **+ New insight** button (top right)
3. Select the insight type (Trends, Funnel, etc.)
4. Configure as described below
5. Click **Save** and give it a name

---

### Insight 1: Completion Rate by Level (Funnel)

**Purpose**: See what percentage of level starts result in completion.

**Step-by-step:**

1. Click **+ New insight** → Select **Funnel**
2. Under "Query steps":
   - **Step 1**: Click "Select event" → type `test_level_start` → select it
   - **Step 2**: Click "+ Add step" → type `test_level_complete` → select it
3. Under "Breakdown by" (right panel):
   - Click **+ Add breakdown**
   - Select **Event properties** → `level_number`
4. Set date range (top right) to **Last 30 days**
5. Click **Save** → Name it "Completion Rate by Level"

**Reading the results:**
- Each bar shows the conversion rate from start → complete for that level
- Lower conversion = harder level
- Click any bar to see the actual user paths

---

### Insight 2: Completion Rate by Level (Trends with Formula)

**Purpose**: Same metric but as a line chart over time.

**Step-by-step:**

1. Click **+ New insight** → Select **Trends**
2. Add first series:
   - Click the event dropdown → type `test_level_complete`
   - Leave aggregation as "Total count"
   - Click **+ Add breakdown** → **Event properties** → `level_number`
3. Add second series:
   - Click **+ Add graph series**
   - Select `test_level_start`
   - Add same breakdown by `level_number`
4. Enable formula:
   - Click **Enable formula mode** (or the `fx` button)
   - Enter formula: `A / B * 100`
   - This calculates: (completions / starts) × 100
5. Click **Save** → Name it "Completion Rate Trend"

**Tips:**
- Series A = first event added, Series B = second
- You can rename series by clicking the series name

---

### Insight 3: Skip Rate by Level

**Purpose**: Identify frustrating levels with high skip rates.

**Step-by-step:**

1. Click **+ New insight** → Select **Trends**
2. Add series A:
   - Event: `test_level_skip`
   - Breakdown by: `level_number`
3. Add series B:
   - Event: `test_level_start`
   - Breakdown by: `level_number`
4. Enable formula mode:
   - Formula: `A / B * 100`
5. Change visualization:
   - Click the chart type dropdown (top of chart area)
   - Select **Bar chart** for easier comparison
6. Click **Save** → Name it "Skip Rate by Level"

**Interpreting:**
- Skip rate > 50% = level is too hard or frustrating
- Skip rate < 10% = level is engaging

---

### Insight 4: Average Duration by Level

**Purpose**: See how long players spend on each level.

**Step-by-step:**

1. Click **+ New insight** → Select **Trends**
2. Configure event:
   - Event: `test_level_complete`
   - Click the aggregation dropdown (shows "Total count")
   - Select **Property average** → `duration_ms`
3. Add breakdown:
   - **Event properties** → `level_number`
4. Add a formula to convert to seconds:
   - Enable formula mode
   - Formula: `A / 1000`
5. Change to **Bar chart** or **Table**
6. Click **Save** → Name it "Avg Completion Time by Level"

---

### Insight 5: Feedback Sentiment Distribution

**Purpose**: See emoji feedback breakdown per level.

**Step-by-step:**

1. Click **+ New insight** → Select **Trends**
2. Configure event:
   - Event: `test_level_feedback`
   - Aggregation: **Total count**
3. Add breakdowns (you can add multiple):
   - First: **Event properties** → `level_number`
   - Second: **Event properties** → `emoji`
4. Change visualization to **Table** for clearer reading
5. Click **Save** → Name it "Feedback by Level"

**Reading the table:**
- Each row shows level + emoji combination with count
- Sort by count to see most common feedback

---

### Insight 6: Sentiment Score (Positive %)

**Purpose**: Calculate a single sentiment percentage per level.

**Step-by-step:**

1. Click **+ New insight** → Select **Trends**
2. Add series A (positive feedback):
   - Event: `test_level_feedback`
   - Click **+ Add filter**
   - Property: `emoji`
   - Operator: **equals**
   - Value: `thumbs_up` (then click + to add `happy`)
   - Breakdown by: `level_number`
3. Add series B (total feedback):
   - Event: `test_level_feedback`
   - No filter
   - Breakdown by: `level_number`
4. Enable formula: `A / B * 100`
5. Click **Save** → Name it "Positive Sentiment %"

---

### Insight 7: Test Mode Sessions Over Time

**Purpose**: Track overall test mode engagement.

**Step-by-step:**

1. Click **+ New insight** → Select **Trends**
2. Configure:
   - Event: `test_session_start`
   - Aggregation: **Unique users** (or Total count for sessions)
3. Set interval to **Day** or **Week**
4. Click **Save** → Name it "Test Mode Usage"

---

### Creating a Dashboard

Combine all insights into a single view:

1. Click **Dashboards** in left sidebar
2. Click **+ New dashboard**
3. Name it "Level Testing Analytics"
4. Click **Add insight** → Select from your saved insights
5. Drag to arrange, resize as needed
6. Recommended layout:
   ```
   ┌─────────────────┬─────────────────┐
   │ Test Mode Usage │ Completion Rate │
   │   (line chart)  │   (bar chart)   │
   ├─────────────────┼─────────────────┤
   │   Skip Rate     │   Avg Duration  │
   │  (bar chart)    │   (bar chart)   │
   ├─────────────────┴─────────────────┤
   │     Feedback Sentiment (table)    │
   └───────────────────────────────────┘
   ```

---

### Using SQL Mode for Advanced Analysis

For complex queries that can't be built with the UI:

1. Click **+ New insight** → Select **SQL**
2. You'll see a query editor with autocomplete
3. Key table: `events` - contains all your events
4. Key columns:
   - `event` - event name (string)
   - `properties` - JSON object with all properties
   - `timestamp` - when event occurred
   - `distinct_id` - user identifier

**Accessing properties in SQL:**
```sql
-- String property
properties.emoji

-- Numeric property (cast if needed)
CAST(properties.duration_ms AS INTEGER)

-- Or use JSONExtract for complex cases
JSONExtractInt(properties, 'duration_ms')
```

**Example: Top 10 levels by quality score**
```sql
SELECT
  properties.level_number as level,
  properties.garble as garble,
  COUNT(*) as attempts,

  -- Completion rate
  SUM(CASE WHEN event = 'test_level_complete' THEN 1 ELSE 0 END) * 100.0
    / COUNT(*) as completion_pct,

  -- Average duration (seconds)
  AVG(CASE WHEN event = 'test_level_complete'
      THEN CAST(properties.duration_ms AS FLOAT) / 1000
      ELSE NULL END) as avg_seconds

FROM events
WHERE event IN ('test_level_start', 'test_level_complete')
  AND timestamp > now() - INTERVAL 30 DAY
GROUP BY properties.level_number, properties.garble
HAVING COUNT(*) >= 5
ORDER BY completion_pct DESC
LIMIT 10
```

---

### Filtering Tips

Add filters to any insight to focus on specific data:

1. Click **+ Add filter** below the event
2. Common filters:
   - `level_number` equals `5` - single level
   - `level_number` greater than `10` - level range
   - `emoji` equals `thumbs_down` - negative feedback only
   - `was_skipped` equals `1` - skipped levels only (note: stored as 1/0)

**Global filters:**
- Use the filter bar at the top of insights to filter all series at once
- Useful for comparing specific date ranges or user segments

---

### Exporting Data

To get raw data for external analysis:

1. Create a SQL insight with your query
2. Click the **⋮** menu (three dots) on the insight
3. Select **Export** → Choose CSV or JSON
4. For ongoing exports, use PostHog's **Data pipelines** feature

---

### Completion Rate by Level

**Insight Type:** Funnel

```
Step 1: test_level_start
Step 2: test_level_complete
Breakdown by: level_number
```

Or use **Trends** with formula:

```
A: test_level_complete (count) grouped by level_number
B: test_level_start (count) grouped by level_number
Formula: A / B * 100
```

### Skip Rate by Level

**Insight Type:** Trends with Formula

```
A: test_level_skip (count) grouped by level_number
B: test_level_start (count) grouped by level_number
Formula: A / B * 100
```

### Average Score by Level

**Insight Type:** Trends

```
Event: test_level_feedback
Aggregation: Average of score_percentage
Breakdown: level_number
Filter: was_skipped = false
```

### Feedback Sentiment by Level

**Insight Type:** Trends

```
Event: test_level_feedback
Aggregation: Count
Breakdown: level_number, emoji
```

Then calculate sentiment score:
- Positive = (thumbs_up + happy) / total
- Negative = (thumbs_down + angry) / total

### Finding Best Levels (SQL in PostHog)

Go to **SQL** in PostHog and run:

```sql
WITH level_stats AS (
  SELECT
    properties.level_number as level_number,
    properties.garble as garble,
    COUNT(*) as total_attempts,

    -- Completion rate
    SUM(CASE WHEN event = 'test_level_complete' THEN 1 ELSE 0 END) as completions,

    -- Skip rate
    SUM(CASE WHEN event = 'test_level_skip' THEN 1 ELSE 0 END) as skips,

    -- Abandonment rate
    SUM(CASE WHEN event = 'test_level_abandoned' THEN 1 ELSE 0 END) as abandons,

    -- Average duration (completed only)
    AVG(CASE WHEN event = 'test_level_complete'
        THEN properties.duration_ms ELSE NULL END) as avg_duration_ms

  FROM events
  WHERE event IN ('test_level_start', 'test_level_complete', 'test_level_skip', 'test_level_abandoned')
    AND timestamp > now() - INTERVAL 30 DAY
  GROUP BY properties.level_number, properties.garble
),

feedback_stats AS (
  SELECT
    properties.level_number as level_number,

    -- Sentiment
    SUM(CASE WHEN properties.emoji IN ('thumbs_up', 'happy') THEN 1 ELSE 0 END) as positive,
    SUM(CASE WHEN properties.emoji IN ('thumbs_down', 'angry') THEN 1 ELSE 0 END) as negative,
    COUNT(*) as total_feedback

  FROM events
  WHERE event = 'test_level_feedback'
    AND timestamp > now() - INTERVAL 30 DAY
  GROUP BY properties.level_number
)

SELECT
  ls.level_number,
  ls.garble,
  ls.total_attempts,

  -- Difficulty metrics
  ROUND(ls.completions * 100.0 / NULLIF(ls.total_attempts, 0), 1) as completion_rate,
  ROUND(ls.skips * 100.0 / NULLIF(ls.total_attempts, 0), 1) as skip_rate,
  ROUND(ls.abandons * 100.0 / NULLIF(ls.total_attempts, 0), 1) as abandon_rate,
  ROUND(ls.avg_duration_ms / 1000.0, 1) as avg_duration_sec,

  -- Sentiment
  ROUND(fs.positive * 100.0 / NULLIF(fs.total_feedback, 0), 1) as positive_pct,

  -- Quality score (higher = better level)
  -- Formula: completion_rate * 0.3 + (100 - skip_rate) * 0.2 + (100 - abandon_rate) * 0.1 + positive_pct * 0.4
  ROUND(
    (ls.completions * 100.0 / NULLIF(ls.total_attempts, 0)) * 0.3 +
    (100 - ls.skips * 100.0 / NULLIF(ls.total_attempts, 0)) * 0.2 +
    (100 - ls.abandons * 100.0 / NULLIF(ls.total_attempts, 0)) * 0.1 +
    (fs.positive * 100.0 / NULLIF(fs.total_feedback, 0)) * 0.4
  , 1) as quality_score

FROM level_stats ls
LEFT JOIN feedback_stats fs ON ls.level_number = fs.level_number
WHERE ls.total_attempts >= 5  -- Minimum sample size
ORDER BY quality_score DESC
LIMIT 20;
```

### Difficulty Tiers Query

```sql
WITH metrics AS (
  -- Same CTE as above
)

SELECT
  level_number,
  garble,
  completion_rate,
  skip_rate,
  CASE
    WHEN completion_rate >= 70 THEN 'Easy'
    WHEN completion_rate >= 30 THEN 'Medium'
    ELSE 'Hard'
  END as difficulty_tier,
  quality_score
FROM metrics
ORDER BY difficulty_tier, quality_score DESC;
```

---

## Firebase Analytics + BigQuery

### Setup
1. Enable BigQuery export in Firebase Console → Project Settings → Integrations
2. Wait 24h for initial data export
3. Go to BigQuery Console

### Schema
Events are exported to: `project_id.analytics_XXXXXX.events_*`

Key fields:
- `event_name` - The event type
- `event_params` - Array of key-value pairs
- `event_timestamp` - Microseconds since epoch

### Helper Function for Parameters

```sql
-- Extract parameter value
CREATE TEMP FUNCTION getParam(params ARRAY<STRUCT<key STRING, value STRUCT<string_value STRING, int_value INT64, float_value FLOAT64, double_value FLOAT64>>>, param_key STRING)
RETURNS STRING AS (
  (SELECT COALESCE(value.string_value, CAST(value.int_value AS STRING), CAST(value.double_value AS STRING))
   FROM UNNEST(params) WHERE key = param_key)
);

CREATE TEMP FUNCTION getParamInt(params ARRAY<STRUCT<key STRING, value STRUCT<string_value STRING, int_value INT64, float_value FLOAT64, double_value FLOAT64>>>, param_key STRING)
RETURNS INT64 AS (
  (SELECT value.int_value FROM UNNEST(params) WHERE key = param_key)
);
```

### Completion Rate by Level

```sql
WITH level_attempts AS (
  SELECT
    getParam(event_params, 'level_number') as level_number,
    getParam(event_params, 'garble') as garble,
    event_name
  FROM `your_project.analytics_XXXXXX.events_*`
  WHERE event_name IN ('test_level_start', 'test_level_complete', 'test_level_skip', 'test_level_abandoned')
    AND _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                          AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
)

SELECT
  level_number,
  garble,
  COUNTIF(event_name = 'test_level_start') as attempts,
  COUNTIF(event_name = 'test_level_complete') as completions,
  COUNTIF(event_name = 'test_level_skip') as skips,
  COUNTIF(event_name = 'test_level_abandoned') as abandons,
  ROUND(COUNTIF(event_name = 'test_level_complete') * 100.0 /
        NULLIF(COUNTIF(event_name = 'test_level_start'), 0), 1) as completion_rate,
  ROUND(COUNTIF(event_name = 'test_level_skip') * 100.0 /
        NULLIF(COUNTIF(event_name = 'test_level_start'), 0), 1) as skip_rate,
  ROUND(COUNTIF(event_name = 'test_level_abandoned') * 100.0 /
        NULLIF(COUNTIF(event_name = 'test_level_start'), 0), 1) as abandon_rate
FROM level_attempts
GROUP BY level_number, garble
HAVING attempts >= 5
ORDER BY completion_rate DESC;
```

### Full Analysis Query

```sql
-- Best levels with difficulty scoring
WITH starts AS (
  SELECT
    getParam(event_params, 'level_number') as level_number,
    getParam(event_params, 'garble') as garble,
    getParamInt(event_params, 'max_score') as max_score,
    getParamInt(event_params, 'word_count') as word_count,
    getParamInt(event_params, 'garble_length') as garble_length
  FROM `your_project.analytics_XXXXXX.events_*`
  WHERE event_name = 'test_level_start'
    AND _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                          AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),

completions AS (
  SELECT
    getParam(event_params, 'level_number') as level_number,
    getParamInt(event_params, 'duration_ms') as duration_ms,
    getParamInt(event_params, 'pop_count') as pop_count
  FROM `your_project.analytics_XXXXXX.events_*`
  WHERE event_name = 'test_level_complete'
    AND _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                          AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),

skips AS (
  SELECT
    getParam(event_params, 'level_number') as level_number,
    getParamInt(event_params, 'current_score') as score_at_skip,
    getParamInt(event_params, 'max_score') as max_score
  FROM `your_project.analytics_XXXXXX.events_*`
  WHERE event_name = 'test_level_skip'
    AND _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                          AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
),

feedback AS (
  SELECT
    getParam(event_params, 'level_number') as level_number,
    getParam(event_params, 'emoji') as emoji,
    getParamInt(event_params, 'score_percentage') as score_percentage
  FROM `your_project.analytics_XXXXXX.events_*`
  WHERE event_name = 'test_level_feedback'
    AND _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY))
                          AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())
)

SELECT
  s.level_number,
  ANY_VALUE(s.garble) as garble,
  ANY_VALUE(s.garble_length) as garble_length,
  ANY_VALUE(s.max_score) as max_score,

  -- Attempt counts
  COUNT(DISTINCT s.level_number) as attempts,
  (SELECT COUNT(*) FROM completions c WHERE c.level_number = s.level_number) as completions,
  (SELECT COUNT(*) FROM skips sk WHERE sk.level_number = s.level_number) as skips,

  -- Rates
  ROUND((SELECT COUNT(*) FROM completions c WHERE c.level_number = s.level_number) * 100.0 / COUNT(*), 1) as completion_rate,
  ROUND((SELECT COUNT(*) FROM skips sk WHERE sk.level_number = s.level_number) * 100.0 / COUNT(*), 1) as skip_rate,

  -- Timing
  ROUND((SELECT AVG(duration_ms) FROM completions c WHERE c.level_number = s.level_number) / 1000, 1) as avg_completion_sec,

  -- Feedback sentiment
  (SELECT COUNTIF(emoji IN ('thumbs_up', 'happy')) FROM feedback f WHERE f.level_number = s.level_number) as positive_feedback,
  (SELECT COUNTIF(emoji IN ('thumbs_down', 'angry')) FROM feedback f WHERE f.level_number = s.level_number) as negative_feedback,

  -- Average score when skipping (how far players get)
  ROUND((SELECT AVG(score_at_skip * 100.0 / NULLIF(max_score, 0)) FROM skips sk WHERE sk.level_number = s.level_number), 1) as avg_skip_score_pct

FROM starts s
GROUP BY s.level_number
HAVING COUNT(*) >= 5
ORDER BY completion_rate DESC;
```

---

## Interpreting Results

### Quality Score Formula

```
quality_score = (completion_rate × 0.3) + ((100 - skip_rate) × 0.2) + ((100 - abandon_rate) × 0.1) + (positive_pct × 0.4)
```

- **80-100**: Excellent level - consider for main game
- **60-80**: Good level - may need minor adjustments
- **40-60**: Average - review feedback for issues
- **< 40**: Poor - likely too hard or frustrating

### Difficulty Classification

| Metric | Easy | Medium | Hard |
|--------|------|--------|------|
| Completion Rate | > 70% | 30-70% | < 30% |
| Avg Score % | > 80% | 50-80% | < 50% |
| Skip Rate | < 20% | 20-40% | > 40% |
| Abandon Rate | < 5% | 5-15% | > 15% |
| Avg Duration | < 30s | 30-60s | > 60s |

### Red Flags

- **High skip rate + negative feedback**: Level is frustrating
- **Low completion + low skip**: Players keep retrying (could be good engagement or bad UX)
- **High completion + negative feedback**: Too easy, boring
- **Very short duration + high completion**: Trivially easy
- **High abandonment rate**: Level causes players to quit test mode entirely - investigate immediately

### Ideal Levels for Main Game

Look for levels with:
- Completion rate: 40-70% (challenging but achievable)
- Skip rate: < 30%
- Positive feedback: > 60%
- Quality score: > 65

---

## Automated Monitoring

### PostHog Dashboards

**Creating the main dashboard:**

1. Go to **Dashboards** → **+ New dashboard**
2. Name: "Garble Level Testing"
3. Add these insights (create if not already saved):

| Insight | Type | Purpose |
|---------|------|---------|
| Test Mode Sessions | Trends (line) | Track daily usage |
| Completion Funnel | Funnel | Overall conversion health |
| Completion Rate by Level | Trends (bar) | Compare level difficulty |
| Skip Rate by Level | Trends (bar) | Find frustrating levels |
| Avg Duration by Level | Trends (bar) | Time investment per level |
| Feedback Sentiment | Trends (table) | Player reactions |
| Quality Score Rankings | SQL (table) | Best levels for main game |

**Setting up alerts:**

1. Open any insight on your dashboard
2. Click **⋮** menu → **Subscribe**
3. Configure:
   - **Frequency**: Daily or Weekly
   - **Condition**: e.g., "Skip rate > 50%"
   - **Delivery**: Email or Slack
4. You'll be notified when levels need attention

**Sharing the dashboard:**

1. Click **Share** on the dashboard
2. Options:
   - **Internal link**: Share with team members
   - **Public link**: View-only link (no login required)
   - **Embed**: Get iframe code for internal tools

### Real-time Debugging

To see events as they arrive during testing:

1. Go to **Activity** → **Live events**
2. Filter by event name: `test_level_start`, `test_level_complete`, etc.
3. Click any event to see full properties
4. Useful for verifying analytics are working correctly

### Firebase/BigQuery Scheduled Queries

Set up a scheduled query to run daily:

```sql
-- Export best levels to a table for easy access
CREATE OR REPLACE TABLE `your_project.analytics.level_rankings` AS
-- (use the full analysis query above)
```

Then create a Data Studio dashboard connected to this table.

---

## Route Analysis (Advanced)

The `route` property in `test_level_complete` contains the sequence of pops and banked words.

Format: `"pos1,pos2,pos3|word1,word2,word3"`

### Parsing Routes in PostHog SQL

```sql
SELECT
  properties.level_number,
  properties.garble,
  properties.route,
  SPLIT(SPLIT(properties.route, '|')[1], ',') as pop_sequence,
  SPLIT(SPLIT(properties.route, '|')[2], ',') as words_found
FROM events
WHERE event = 'test_level_complete'
LIMIT 100;
```

### Finding Optimal vs Actual Routes

Compare player routes to the optimal path (stored in game code via `Scorer.bestPath()`).

This can reveal:
- Where players diverge from optimal
- Common mistakes
- Whether the optimal path is discoverable
