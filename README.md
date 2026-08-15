# faultline

[![CI](https://github.com/Temikus/faultline/actions/workflows/ci.yml/badge.svg)](https://github.com/Temikus/faultline/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

An HTTP server that fails on purpose.

It is the thing under test when what you are actually testing is how something
*else* reacts to partial failure — a canary that ought to be rolled back, an
alert that ought to fire, a load balancer that ought to shed a bad backend, a
retry policy nobody has ever watched work. Two numbers describe it: how often it
returns 500, and how slow it is.

```bash
docker run --rm -p 8080:8080 -e FAIL_RATE=0.35 -e LATENCY_MS=50 ghcr.io/temikus/faultline:latest
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/healthz
```

Both `/healthz` and `/` serve the same thing, so it does not matter which one
your probe points at.

| Variable | Default | |
|---|---|---|
| `FAIL_RATE` | `0` | probability of returning 500, `0`–`1` |
| `LATENCY_MS` | `0` | delay added before responding |
| `PORT` | `8080` | listen port |

An unparseable value falls back to the default rather than refusing to start. A
fault injector that will not boot because of a typo in a manifest has failed in
the one way it was not asked to.

## Profile tags

Sometimes you do not want to configure the fault — you want the deployed image
to *be* the fault, so that the tag which was rolled out is a complete account of
what the workload does. That matters when the system under test is a pipeline
making decisions from what it observes: fault config living in a manifest can
silently contradict the image, and then you are debugging your test harness
instead of the thing you meant to test.

| Tag | `FAIL_RATE` | `LATENCY_MS` | For |
|---|---|---|---|
| `blue-stable` | 0 | 10ms | the incumbent — what is already running |
| `green-stable` | 0 | 12ms | a candidate that is fine; promoting it should succeed |
| `green-flaky` | 0.075 | 55ms | a candidate that is marginal — enough failures to notice, not enough to be sure from a small sample |
| `green-broken` | 0.35 | 15ms | a candidate that is unambiguously bad |
| `green-slow` | 0 | 400ms | a candidate that never fails and is simply too slow |
| `plain`, `latest` | 0 | 0 | configure it yourself |

`green-slow` is worth having because every other profile degrades by returning
500s. A latency regression is a different thing to detect — error-rate alarms
never fire, and a system that only watches for failures will promote it
happily.

Blue and green are the usual deployment roles: blue is what is serving, green is
what you are considering. Two healthy tags exist because a promotion has to
visibly move the image even when nothing is wrong — if the happy path deployed
the same tag it started on, it would prove nothing.

`green-flaky` is the interesting one. Anything can catch a backend that fails a
third of its requests; the question worth testing is what your system does when
the signal is weak enough that the honest answer is "not enough evidence yet".

### Pinning

Every profile publishes a moving tag and a pinned one:

```
ghcr.io/temikus/faultline:green-broken        # newest build of that profile
ghcr.io/temikus/faultline:0.1.0-green-broken  # that version of that profile
```

The plain build answers to two more, for anyone reaching for the image without
caring about profiles:

```
ghcr.io/temikus/faultline:latest              # newest, configure at run time
ghcr.io/temikus/faultline:0.1.0               # same image as 0.1.0-plain
```

Point a demo at the moving profile tag. Pin the version-qualified one when a
result has to still mean the same thing a year from now.

## Development

```bash
just                # list recipes
just check          # lint + tests + image build
just serve 0.35 15  # run locally, failing a third of requests
just probe          # hit it 20 times and count the failures
just release minor  # tag and push, which publishes every profile
```

`just release [patch|minor|major]` bumps the latest tag and pushes it, and the
push is what triggers a publish. `Actions → publish → Run workflow` does the
same thing for a version you name.

The images are deliberately not rebuilt on every commit: they are fixtures, and
a rebuild of `blue-stable` while something is mid-test would move the baseline
underneath it.

## Who uses it

Written for [covenant](https://github.com/Temikus/covenant), whose canary demo
deploys `green-broken`, watches its own probe conclude the rollout is bad, and
refuses to finish the run until a rollback to `blue-stable` has actually
happened. It has no dependency on that project.
