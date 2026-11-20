import pytest

import ai_prompts
import math_skill
from math_skill import Attempt


def test_no_attempts_start_at_a_gentle_level():
    assert math_skill.mastery([]) is None
    assert math_skill.recommended_difficulty([]) == math_skill.START_DIFFICULTY
    assert math_skill.label(None, 0) == "new"


def test_newer_attempts_weigh_more():
    improving = [Attempt(2, 1.0), Attempt(2, 0.0)]  # newest first
    declining = [Attempt(2, 0.0), Attempt(2, 1.0)]
    assert math_skill.mastery(improving) > 0.5 > math_skill.mastery(declining)


def test_difficulty_rises_after_solid_results_and_falls_after_weak_ones():
    assert math_skill.recommended_difficulty([Attempt(3, 1.0)] * 4) == 4
    assert math_skill.recommended_difficulty([Attempt(3, 0.0)] * 2) == 2
    assert math_skill.recommended_difficulty([Attempt(3, 0.6)] * 4) == 3


@pytest.mark.parametrize("attempts, expected", [([Attempt(5, 1.0)] * 5, 5), ([Attempt(1, 0.0)] * 5, 1)])
def test_difficulty_stays_within_bounds(attempts, expected):
    assert math_skill.recommended_difficulty(attempts) == expected


def test_labels():
    assert math_skill.label(0.9, 4) == "strength"
    assert math_skill.label(0.3, 3) == "weakness"
    assert math_skill.label(0.9, 1) == "practising"


def test_scores_are_clamped():
    assert math_skill.mastery([Attempt(2, 3.0)]) == 1.0
    assert math_skill.mastery([Attempt(2, -1.0)]) == 0.0


def test_math_prompts_carry_level_difficulty_and_weaknesses():
    task = ai_prompts.math_task("upper", "Ableitungen", 4, "German", "Kettenregel", "f(x)=x²")
    assert "Abitur" in task and "Difficulty 4" in task and "Kettenregel" in task and "f(x)=x²" in task and "LaTeX" in task
    check = ai_prompts.math_check("middle", "Prozent", "20 % von 50?", "50 · 0,2", "10", "1. 50 · 0,2 = 10", "10", "German")
    assert "Accept every correct method" in check and "firstErrorStep" in check and "50 · 0,2 = 10" in check
