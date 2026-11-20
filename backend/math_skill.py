"""Strengths and weaknesses in maths: mastery per topic and the difficulty the next task should have.

Pure functions over recent attempts, so they can be tested without a database.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, Optional

MIN_DIFFICULTY = 1
MAX_DIFFICULTY = 5
START_DIFFICULTY = 2
RECENT_ATTEMPTS = 20
# The newest attempt counts fully, each older one a bit less.
DECAY = 0.85


@dataclass(frozen=True)
class Attempt:
    difficulty: int
    score: float  # 0.0 (wrong) … 1.0 (fully correct)


def mastery(attempts: Iterable[Attempt]) -> Optional[float]:
    """Weighted average score of the newest attempts first (0…1), or None without attempts."""
    total = weight_sum = 0.0
    weight = 1.0
    for attempt in list(attempts)[:RECENT_ATTEMPTS]:
        total += weight * max(0.0, min(1.0, attempt.score))
        weight_sum += weight
        weight *= DECAY
    return total / weight_sum if weight_sum else None


def recommended_difficulty(attempts: list[Attempt]) -> int:
    """Next difficulty: up after solid results, down after weak ones, based on the recent level (newest first)."""
    if not attempts:
        return START_DIFFICULTY
    recent = attempts[:5]
    level = round(sum(a.difficulty for a in recent) / len(recent))
    score = mastery(recent) or 0.0
    if len(attempts) >= 3 and score >= 0.8:
        level += 1
    elif score < 0.5:
        level -= 1
    return max(MIN_DIFFICULTY, min(MAX_DIFFICULTY, level))


def label(score: Optional[float], attempts: int) -> str:
    """strength, weakness, practising or new: how a topic is shown to the learner."""
    if score is None or attempts == 0:
        return "new"
    if attempts >= 3 and score >= 0.75:
        return "strength"
    if attempts >= 2 and score < 0.5:
        return "weakness"
    return "practising"
