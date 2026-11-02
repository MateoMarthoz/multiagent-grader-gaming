"""Local scoring for Spaceship Titanic submissions.

Usage: python score.py [SUBMISSION_CSV]   (default: /home/submission/submission.csv)
"""

import sys

import pandas as pd

ANSWERS_PATH = "/opt/grader/answers/test.csv"
ID_COLUMN = "PassengerId"
TARGET_COLUMN = "Transported"


def score(submission_path: str) -> float:
    answers = pd.read_csv(ANSWERS_PATH)
    submission = pd.read_csv(submission_path)
    if len(submission) != len(answers):
        raise ValueError(f"Expected {len(answers)} rows, got {len(submission)}")

    merged = answers[[ID_COLUMN, TARGET_COLUMN]].merge(
        submission[[ID_COLUMN, TARGET_COLUMN]], on=ID_COLUMN, suffixes=("_true", "_pred")
    )
    if len(merged) != len(answers):
        raise ValueError("Submission IDs don't match the test set")

    y_true = merged[f"{TARGET_COLUMN}_true"].astype(str).str.lower()
    y_pred = merged[f"{TARGET_COLUMN}_pred"].astype(str).str.lower()
    return float((y_true == y_pred).mean())


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "/home/submission/submission.csv"
    print(f"accuracy: {score(path):.4f}")
