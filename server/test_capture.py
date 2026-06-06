import asyncio
from stream import capture_loop, _clients

class DummyWebSocket:
    async def send(self, data):
        print("Sent frame of size:", len(data))

async def test_capture():
    _clients.add(DummyWebSocket())
    try:
        await asyncio.wait_for(capture_loop(), timeout=2.0)
    except asyncio.TimeoutError:
        print("Test finished (timeout)")

asyncio.run(test_capture())
