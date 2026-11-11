# Questions for an agent

Questions a store owner asks an AI agent that answers through
dactopus-ossie-clickhouse over the commerce model, and how to tell a
right answer from a wrong one over your own data. Use them to check your
agent, your model or prompt changes, and the model of a new release.

## The questions

`commerce.yaml` holds each question with its difficulty, what the data
must hold for it to test anything, and its expected answer. The
difficulties:

- **total**: one number over all time or a named period.
- **breakdown**: a number by a dimension, a top list, by month.
- **relative_period**: yesterday, last month, the last 7 days.
- **stores_currencies**: several stores in different currencies, whose
  amounts are never added up or compared.
- **not_in_model**: data the model does not have; the right answer says
  so and puts nothing similar in its place.
- **absence**: customers who stopped buying, products that never sold.
- **ratio**: a share or a change, including shares the model has no
  metric for, which the agent must not compute itself.
- **unclear_store**: a store named by a word, a currency or a platform,
  or not at all; the agent answers or asks which store is meant.
- **counting_rule**: how the stores count orders, dates and discounts.
- **related_filter**: a metric of one table filtered by another, such as
  the orders that include a category.

A question's expected answer is a set of queries of the model, so a
change of a metric's definition moves the expected numbers with it. A
question with no number to state (a refusal, a question back, a rule)
has a rubric: what a right answer says.

## Running them

1. **Describe the deployment.** Copy `deployment.example.yaml`: the model
   files, the time zone the model is served in, your databases (one store
   each, or unions of two) with what their data provides, and the
   parameters the questions use, such as a category of your catalogue.
   A question that no database fits is skipped.
2. **Work out the expected answers** for the day you ask the agent, in
   the deployment's zone:

   ```bash
   uv run evals/reference.py evals/commerce.yaml my-deployment.yaml --today 2026-11-11 > expected.json
   ```

   It runs `dactopus-ossie-clickhouse query`, which must be on the PATH,
   against the server of `CLICKHOUSE_HOST`, `CLICKHOUSE_PORT` (HTTP),
   `CLICKHOUSE_USER` and `CLICKHOUSE_PASSWORD`.
3. **Ask your agent** each entry's `question` over its `database`, a
   fresh session each, and write its final answers as JSON lines:
   `{"id": ..., "database": ..., "answer": ...}`.
4. **Grade them:**

   ```bash
   uv run evals/grade.py expected.json answers.jsonl > verdicts.jsonl
   ```

   It prints a verdict per answer and the count of right answers per
   difficulty.

## How an answer is graded

- **Numbers.** A right answer states every number of one accepted
  reading of the question, at the precision it chooses: 107.82 and 108
  both state 107.818. A share may be a percentage. Text values, such as
  a product's title or a currency's code, must appear too. Where a list
  is cut at a tie, any of the tied rows may be listed.
- **Forbidden numbers.** A question about stores in two currencies fails
  when the answer states the sum or average over both.
- **Rubrics.** A Claude model (`--judge-model`, by default
  `claude-haiku-5-5`) reads the answer and the rubric and decides; set
  `ANTHROPIC_API_KEY`. Answers to questions without a rubric need no key.
- **Empty answers.** Where the data has no rows for the question, the
  right answer says there are none.

`tests/check_evals.py` works out every expected answer over the
canonical tables of the Shopify and WooCommerce packages in CI, so a
question whose metric or field the model no longer has fails there.
