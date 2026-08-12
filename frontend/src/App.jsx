import { useCallback, useState } from 'react'

const SCENARIOS = [
  {
    id: 'n-plus-one',
    number: 1,
    title: 'Order listing',
    endpoint: '/api/orders?limit=50',
    watch: 'SQL queries',
    hint: 'One request. Count the SQL statements it takes to answer it.',
    doc: 'docs/01-scenario-n-plus-one.md',
  },
  {
    id: 'missing-index',
    number: 2,
    title: 'Order search',
    endpoint: '/api/orders/search?status=SHIPPED&withinHours=48&limit=50',
    watch: 'Server time',
    hint: 'Exactly one SQL statement. The Java is fine. The plan is not.',
    doc: 'docs/02-scenario-missing-index.md',
  },
]

function ScenarioCard({ scenario }) {
  const [state, setState] = useState({ status: 'idle' })

  const run = useCallback(async () => {
    setState({ status: 'running' })
    const startedAt = performance.now()
    try {
      const response = await fetch(scenario.endpoint)
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }
      const body = await response.json()
      setState({
        status: 'done',
        roundTripMs: Math.round(performance.now() - startedAt),
        queryCount: body.sqlQueryCount,
        serverMs: body.serverMillis,
        rows: body.data.length,
      })
    } catch (error) {
      setState({ status: 'error', message: String(error.message || error) })
    }
  }, [scenario.endpoint])

  return (
    <article className="card">
      <header className="card__head">
        <span className="card__badge">Scenario {scenario.number}</span>
        <h2 className="card__title">{scenario.title}</h2>
      </header>

      <p className="card__hint">{scenario.hint}</p>
      <code className="card__endpoint">GET {scenario.endpoint}</code>

      <button className="card__button" onClick={run} disabled={state.status === 'running'}>
        {state.status === 'running' ? 'Running…' : 'Run request'}
      </button>

      {state.status === 'error' && (
        <p className="card__error">
          {state.message}. Is the backend up? Try <code>make logs</code>.
        </p>
      )}

      {state.status === 'done' && (
        <dl className="metrics">
          <Metric
            label="SQL queries"
            value={state.queryCount}
            emphasis={scenario.watch === 'SQL queries'}
          />
          <Metric
            label="Server time"
            value={`${state.serverMs} ms`}
            emphasis={scenario.watch === 'Server time'}
          />
          <Metric label="Round trip" value={`${state.roundTripMs} ms`} />
          <Metric label="Rows" value={state.rows} />
        </dl>
      )}

      <footer className="card__foot">
        Walkthrough: <code>{scenario.doc}</code>
      </footer>
    </article>
  )
}

function Metric({ label, value, emphasis = false }) {
  return (
    <div className={emphasis ? 'metric metric--emphasis' : 'metric'}>
      <dt className="metric__label">{label}</dt>
      <dd className="metric__value">{value}</dd>
    </div>
  )
}

export default function App() {
  return (
    <main className="page">
      <header className="page__head">
        <h1 className="page__title">GitHub Copilot scalability demo</h1>
        <p className="page__lede">
          Two deliberately planted performance problems. Run each one, note the number, then let
          Copilot find and fix it. The point of the demo is the difference between what Copilot
          says from source code alone and what it says once it can read the database.
        </p>
      </header>

      <section className="grid">
        {SCENARIOS.map((scenario) => (
          <ScenarioCard key={scenario.id} scenario={scenario} />
        ))}
      </section>

      <footer className="page__foot">
        Start with <code>docs/00-setup.md</code>. Nothing here is a benchmark of PostgreSQL, Spring
        Boot, or React. It is a benchmark of your own workflow.
      </footer>
    </main>
  )
}
