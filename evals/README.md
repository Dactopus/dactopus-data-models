# Questions for an agent

Questions people ask an AI agent that answers through
dactopus-ossie-clickhouse over the commerce, web analytics and IoT
models, and how to tell a right answer from a wrong one over your own
data. Ask your agent the questions, grade its answers, and see where it
goes wrong: a wrong number, two currencies added up, a percentage it
made up, a store it picked instead of asking which one was meant. Run
them again after you change the agent's model or prompt, or upgrade the
models, to see what got better and what broke.

## The questions

`commerce.yaml`, `web_analytics.yaml` and `iot.yaml` hold the questions
of each model. A question has its text, its difficulty (`type`), what
the data must hold for it to test anything, and its expected answer:
the queries of the model that give the numbers, worked out over your
databases for the day you ask. A change of a metric's definition moves
the expected numbers with it. A question whose right answer is no
number (a refusal, a question back, a rule) has a rubric instead: what
a right answer says and what fails it.

The difficulties:

- **total**: one number over all time or a named period.
- **breakdown**: a number by a dimension, a top list, by month.
- **relative_period**: yesterday, last month, the last 7 days.
- **stores_currencies**: several stores, sites or sensor networks;
  amounts in different currencies are never added up or compared, ids
  repeat across them.
- **not_in_model**: data the model does not have; the right answer says
  so and puts nothing similar in its place.
- **absence**: customers who stopped buying, products that never sold,
  sensors that went quiet.
- **ratio**: a share or a change. Where the model has no metric for it,
  the agent gives the numbers it has and does not compute the share
  itself.
- **unclear_store**: a store or site named by a word, a currency or a
  platform, or not at all; the agent answers where a label names it and
  asks which one is meant where none does.
- **counting_rule**: how the stores count orders, dates and discounts.
- **related_filter**: a metric of one table filtered by another, such as
  the orders that include a category.

## Running them

You need dactopus-ossie-clickhouse on the PATH, the models your agent is
served, and the ClickHouse server your packages built into, named by
`CLICKHOUSE_HOST`, `CLICKHOUSE_PORT` (HTTP), `CLICKHOUSE_USER` and
`CLICKHOUSE_PASSWORD`.

### 1. Describe your deployment

Copy the example of the domain, `deployment.<domain>.example.yaml`
(`commerce`, `web_analytics` or `iot`), and edit it:

- **models**: the model files your agent is served, and beside them
  `time_zone`, the zone the executor serves them in
  (`OSSIE_CLICKHOUSE_TIME_ZONE`).
- **databases**: each database the agent is asked over, with `stores`
  (how many stores, sites or networks it holds) and `provides` (what its
  data has). A question is asked over every database whose `stores`
  match and whose `provides` hold all it `requires`; a question no
  database fits is skipped and listed on stderr. Declare only what your
  data has: a question asked over data that lacks it has an empty or
  meaningless expected answer.
- **params**: the words and values the questions use: a category of
  your catalogue, a month whose 90 days are over, the labels of your
  stores and the words people call them by. The example's comments name
  each parameter and each value of `provides`; a parameter a question
  needs and the deployment does not give fails that question with its
  name.
- **labels**, a key of each database: `named` where a label names the
  store (`uk_outlet`), `opaque` where none does (`store_1`). The questions about an unclear
  store expect an answer in the first case and a question back in the
  second. With one kind of labels only, they test half of that.

The examples describe the databases CI fills from the test data.

### 2. Work out the expected answers

For the day you ask the agent, in the deployment's zone:

```bash
uv run evals/reference.py evals/commerce.yaml my-deployment.yaml --today 2026-11-11 > expected.json
```

Each entry is one question over one database: the question as asked,
with the parameters filled in, and its expected rows. "Yesterday", "last
month" and "the last 7 days" are counted from `--today`. Ask every
question on that day, with the executor in the deployment's zone: a run
that crosses midnight there needs the expected answers of the next day
for the answers given after it.

### 3. Ask your agent

Ask each entry's `question` over its `database`, as it is, in a fresh
session with no earlier messages. Serve the agent the models through
`dactopus-ossie-clickhouse serve`, with `OSSIE_CLICKHOUSE_URL` naming the
entry's database and `OSSIE_CLICKHOUSE_TIME_ZONE` the deployment's zone.
Give it no other tools if you want to compare runs. Write each final
answer as a line of JSON:

```json
{"id": "net-sales-all-time", "database": "shop", "answer": "The store has made 13,693.68 USD ..."}
```

The repository ships no program that asks an agent: that is your
agent's own API.

### 4. Grade the answers

```bash
uv run evals/grade.py expected.json answers.jsonl > verdicts.jsonl
```

Numbers are checked by code. A rubric needs a reviewing model, and
there are three ways to give one:

- **Claude** (the default): `--judge-model`, by default
  `claude-haiku-5-5`, through the Anthropic API; set `ANTHROPIC_API_KEY`.
- **A command of your own**: `--judge-command "python3 my_judge.py"` runs
  it through a shell for each answer to judge. It gets the task as JSON
  on stdin and prints its verdict as JSON:

  ```json
  {"question": "...", "criterion": "...", "answer": "...", "prompt": "..."}
  {"passed": true, "reason": "..."}
  ```

  `prompt` is the text the Claude judge gets, the question, criterion
  and answer in it; give it to your model as it is to judge by the same
  rules.
- **None**: `--no-judge` checks numbers only. An answer that needs a
  rubric is not graded and counts apart.

Judges differ on answers at the edge of a rubric, and one judge may
differ from itself between runs: compare runs graded by the same judge.

## Reading the verdicts

Each line of `verdicts.jsonl` is one answer: `passed` is `true`, `false`
or `null` (not graded), and `reasons` says why:

- `missing <metric> <value>`: a number or a name of the expected answer
  is not in it, listed for each accepted reading;
- `states forbidden <metric> <value>`: the answer states a number it
  must not, such as a sum over two currencies;
- `rubric: ...`: the reviewing model's reason the answer fails its
  rubric;
- `not graded: ...`: the rubric that needed a judge, with `--no-judge`.

Stderr counts the right answers per difficulty.

## How an answer is graded

- **Numbers.** A right answer states every number of one accepted reading
  of the question, at the precision it chooses: 107.82 and 108 both state
  107.818. A share may be written as a percentage. Dates, years, list
  markers and the question's own numbers ("the last 7 days") do not
  count as stated values. A zero is stated by 0, zero, none or nothing.
  Where the question asks in other units than the model keeps (hPa for
  Pa), the expected value is converted.
- **Names.** Text values of the expected answer, such as a product's
  title or a currency's code, must appear as whole words, without regard
  to case, punctuation, a leading article or a URL's scheme. A code may
  be written as one of the aliases its query gives (Returning for
  repeat, United States for US), a category path by its last category
  where no other path of the answer ends in that name, a URL by its tail
  after an ellipsis. Where a list is cut at a tie, any of the tied rows
  may be listed.
- **Forbidden numbers.** A question about stores in two currencies fails
  when the answer states the sum or average over both.
- **Empty answers.** Where the data has no rows for the question or a
  part of it, the right answer says there are none.

The set checks the agent: the expected answers come from the model, so a wrong definition in it would not show here. The model's
numbers are checked against numbers derived by hand from the test data
of each package (`tests/<source>/`).

`tests/check_evals.py` works out every expected answer in CI: commerce
over the canonical tables of the Shopify and WooCommerce packages, web
analytics and IoT over the tables their CI jobs build from the fixtures.
A question whose metric or field the model no longer has fails there.
