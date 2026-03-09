#!/usr/bin/env python3
import os
import sys


def main():
    if len(sys.argv) < 2:
        print("Usage: python script.py <extension>")
        print("Example: python script.py lua")
        sys.exit(1)

    ext = sys.argv[1].strip().lower()
    if not ext:
        print("Error: Extension cannot be empty")
        sys.exit(1)

    # 确保扩展名不带点（如用户输入 .lua 会自动处理）
    if ext.startswith("."):
        ext = ext[1:]

    base_dir = os.getcwd()
    print(f"Scanning for .{ext} files in {base_dir}...\n")

    # 遍历所有文件
    for root, _, files in os.walk(base_dir):
        for file in files:
            # 检查文件扩展名（不区分大小写）
            if os.path.splitext(file)[1][1:].lower() == ext:
                file_path = os.path.join(root, file)
                rel_path = os.path.relpath(file_path, base_dir)
                # 统一使用正斜杠（兼容 Windows/Mac/Linux）
                rel_path = rel_path.replace("\\", "/")

                # 打印 Markdown 格式标题
                print(f"# ./{rel_path}")
                print(f"```{ext}")

                # 读取并打印文件内容
                try:
                    with open(file_path, "r", encoding="utf-8") as f:
                        print(f.read(), end="")
                except Exception as e:
                    print(f"ERROR: Failed to read file - {str(e)}")

                print("```\n")  # 结束代码块并添加空行


if __name__ == "__main__":
    main()
