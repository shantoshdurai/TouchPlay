import asyncio
import websockets

async def test_stream():
    try:
        async with websockets.connect("ws://127.0.0.1:8767") as ws:
            print("Connected to stream!")
            frame = await asyncio.wait_for(ws.recv(), timeout=2.0)
            print("Received frame of size:", len(frame))
    except Exception as e:
        print("Error:", e)

asyncio.run(test_stream())
