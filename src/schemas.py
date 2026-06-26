from pydantic import BaseModel, constr


class PredictionRequest(BaseModel):
    text: constr(strip_whitespace=True, min_length=1)


class PredictionResponse(BaseModel):
    label: str
    score: float