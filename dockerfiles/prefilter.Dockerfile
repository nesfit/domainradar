ARG SRC_DIR=input

FROM docker.io/python:3.11-alpine AS python-base

ENV PYTHONUNBUFFERED=1 \
    # prevents python creating .pyc files
    # PYTHONDONTWRITEBYTECODE=1 \
    # pip
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100 \
    # poetry
    POETRY_VERSION=1.8.2 \
    POETRY_HOME="/opt/poetry" \
    POETRY_VIRTUALENVS_IN_PROJECT=1 \
    POETRY_VIRTUALENVS_CREATE=1 \
    POETRY_NO_INTERACTION=1 \
    POETRY_CACHE_DIR="/tmp/poetry_cache" \
    PYSETUP_PATH="/opt/pysetup" \
    VENV_PATH="/opt/pysetup/.venv"

ENV PATH="$POETRY_HOME/bin:$VENV_PATH/bin:$PATH"

#SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

FROM python-base AS builder

RUN apk update && \
    apk add --no-interactive \
    # deps for installing poetry
    curl \
    # deps for building python deps
    build-base \
    postgresql16 libpq-dev

# Install poetry
RUN --mount=type=cache,target=$POETRY_CACHE_DIR \
    curl -sSL https://install.python-poetry.org | python3 -

FROM builder AS deps
ARG SRC_DIR

# Copy project requirement files here to ensure they will be cached
WORKDIR $PYSETUP_PATH

COPY ./${SRC_DIR}/poetry.lock ./${SRC_DIR}/pyproject.toml ./

# Install runtime deps (uses $POETRY_VIRTUALENVS_IN_PROJECT internally)
RUN --mount=type=cache,target=$POETRY_CACHE_DIR \
    poetry install --without=dev

FROM builder AS production
ARG SRC_DIR

COPY --from=deps $PYSETUP_PATH $PYSETUP_PATH
COPY ./${SRC_DIR}/ /app/
WORKDIR /app
RUN --mount=type=cache,target=$POETRY_CACHE_DIR \
    poetry install
ENTRYPOINT ["poetry", "run", "prefilter"]