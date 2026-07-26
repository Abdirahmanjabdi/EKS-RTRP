from datetime import datetime
from enum import Enum
import uvicorn
from fastapi import FastAPI, status
from pydantic import BaseModel, Field

app = FastAPI(title="Trade API v0", version="0.1.0")

class Side(str, Enum):
    BUY = "buy"
    SELL = "sell"

class Trade(BaseModel):
    symbol: str = Field(..., min_length=1, description="The instrument symbol, e.g., AAPL, EURUSD")
    side: Side = Field(..., description="Order side: buy or sell")
    quantity: float = Field(..., gt=0, description="Execution quantity, must be greater than 0")
    price: float = Field(..., gt=0, description="Execution price, must be greater than 0")
    timestamp: datetime = Field(..., description="Execution timestamp in UTC")

@app.get("/health", status_code=status.HTTP_200_OK)
def health_check():
    return {"status": "ok"}

@app.post("/trades", status_code=status.HTTP_201_CREATED)
def create_trade(trade: Trade):
    return {
        "status": "acknowledged",
        "data": trade
    }

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)