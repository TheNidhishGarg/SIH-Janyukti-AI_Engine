import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Every test run gets a throwaway database and the offline engine, so tests are
# deterministic and need neither an API key nor a model download.
os.environ["DATABASE_URL"] = "sqlite+aiosqlite:///./test_janyukti.db"
os.environ["USE_LOCAL_EMBEDDINGS"] = "false"
os.environ["GEMINI_API_KEY"] = ""

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient


@pytest.fixture(scope="session")
def anyio_backend():
    return "asyncio"


@pytest_asyncio.fixture(scope="session")
async def seeded_app():
    if os.path.exists("./test_janyukti.db"):
        os.remove("./test_janyukti.db")

    from app.seed import seed

    await seed(with_challenges=True, analyze=True)

    import main

    async with main.app.router.lifespan_context(main.app):
        yield main.app

    if os.path.exists("./test_janyukti.db"):
        try:
            os.remove("./test_janyukti.db")
        except PermissionError:
            pass


@pytest_asyncio.fixture
async def client(seeded_app):
    async with AsyncClient(
        transport=ASGITransport(app=seeded_app), base_url="http://test"
    ) as c:
        yield c


async def _login(client, email: str) -> dict:
    r = await client.post("/auth/login", json={"email": email, "password": "janyukti123"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest_asyncio.fixture
async def citizen(client):
    return await _login(client, "citizen@janyukti.in")


@pytest_asyncio.fixture
async def admin(client):
    return await _login(client, "admin@janyukti.in")


@pytest_asyncio.fixture
async def university(client):
    return await _login(client, "university@janyukti.in")


@pytest_asyncio.fixture
async def industry(client):
    return await _login(client, "industry@janyukti.in")
