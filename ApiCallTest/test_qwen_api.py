#!/usr/bin/env python3
"""
Simple interactive API connectivity test for Qwen (DashScope compatible OpenAI API).

Usage:
1. pip install openai
2. python3 ApiCallTest/test_qwen_api.py
"""

import os
import sys
from openai import OpenAI

BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
MODEL = "qwen3.5-plus"


def build_client() -> OpenAI:
    api_key = os.getenv("DASHSCOPE_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("Missing API key. Set DASHSCOPE_API_KEY before running this script.")
    return OpenAI(api_key=api_key, base_url=BASE_URL)


def ask_once(client: OpenAI, user_input: str) -> str:
    # Default: non-thinking mode
    # To switch to thinking mode, change enable_thinking to True.
    completion = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": user_input}],
        extra_body={"enable_thinking": False},
        stream=False,
    )

    content = completion.choices[0].message.content
    return content.strip() if content else ""


def main() -> int:
    print("Qwen API connectivity test (non-thinking mode)")
    print("Type your message and press Enter. Type 'exit' to quit.\n")

    try:
        client = build_client()
    except Exception as exc:
        print(f"[Init Failed] {exc}")
        return 1

    while True:
        try:
            user_input = input("You> ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nBye.")
            return 0

        if not user_input:
            continue
        if user_input.lower() in {"exit", "quit"}:
            print("Bye.")
            return 0

        try:
            reply = ask_once(client, user_input)
            print(f"AI > {reply}\n")
        except Exception as exc:
            print(f"[Request Failed] {exc}\n")


if __name__ == "__main__":
    sys.exit(main())
