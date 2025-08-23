#!/usr/bin/env python3
"""
防盗链配置管理器
提供安全的防盗链配置添加、删除和查询功能
"""

import sys
import re
import os
import json
from typing import List, Tuple, Optional

class HotlinkManager:
    def __init__(self, conf_file: str):
        self.conf_file = conf_file
        self.backup_file = f"{conf_file}.hotlink.bak"
        self.hotlink_marker = "# 防盗链配置"
        self.hotlink_end_marker = "    }"
        
    def backup_config(self) -> bool:
        """备份配置文件"""
        try:
            if os.path.exists(self.conf_file):
                with open(self.conf_file, 'r', encoding='utf-8') as src:
                    with open(self.backup_file, 'w', encoding='utf-8') as dst:
                        dst.write(src.read())
                return True
        except Exception as e:
            print(f"备份配置文件失败: {e}", file=sys.stderr)
        return False
    
    def restore_config(self) -> bool:
        """恢复配置文件"""
        try:
            if os.path.exists(self.backup_file):
                with open(self.backup_file, 'r', encoding='utf-8') as src:
                    with open(self.conf_file, 'w', encoding='utf-8') as dst:
                        dst.write(src.read())
                return True
        except Exception as e:
            print(f"恢复配置文件失败: {e}", file=sys.stderr)
        return False
    
    def read_config(self) -> List[str]:
        """读取配置文件"""
        try:
            with open(self.conf_file, 'r', encoding='utf-8') as f:
                return f.readlines()
        except Exception as e:
            print(f"读取配置文件失败: {e}", file=sys.stderr)
            return []
    
    def write_config(self, lines: List[str]) -> bool:
        """写入配置文件"""
        try:
            with open(self.conf_file, 'w', encoding='utf-8') as f:
                f.writelines(lines)
            return True
        except Exception as e:
            print(f"写入配置文件失败: {e}", file=sys.stderr)
            return False
    
    def find_server_blocks(self, lines: List[str]) -> List[Tuple[int, int]]:
        """查找所有server块的位置"""
        server_blocks = []
        brace_stack = []
        
        for i, line in enumerate(lines):
            if re.match(r'\s*server\s*{', line):
                brace_stack.append(i)
            elif '{' in line and not re.match(r'\s*server\s*{', line):
                brace_stack.append(None)
            elif '}' in line:
                if brace_stack:
                    start = brace_stack.pop()
                    if start is not None:
                        server_blocks.append((start, i))
        
        return server_blocks
    
    def find_ssl_server_block(self, lines: List[str], server_blocks: List[Tuple[int, int]]) -> Optional[Tuple[int, int]]:
        """查找SSL server块"""
        for start, end in server_blocks:
            for i in range(start, end + 1):
                if re.search(r'listen\s+443\s+ssl;', lines[i]):
                    return (start, end)
        return None
    
    def find_hotlink_config(self, lines: List[str]) -> Optional[Tuple[int, int]]:
        """查找现有的防盗链配置"""
        start_line = None
        end_line = None
        
        for i, line in enumerate(lines):
            if self.hotlink_marker in line:
                start_line = i
                # 查找对应的结束大括号
                brace_count = 0
                for j in range(i + 1, len(lines)):
                    if '{' in lines[j]:
                        brace_count += 1
                    elif '}' in lines[j]:
                        brace_count -= 1
                        if brace_count == 0:
                            end_line = j
                            break
                break
        
        return (start_line, end_line) if start_line is not None and end_line is not None else None
    
    def generate_hotlink_config(self, referers: str) -> str:
        """生成防盗链配置"""
        return (
            f"    {self.hotlink_marker}\n"
            "    location ~* \\.(gif|jpg|jpeg|png|bmp|swf|flv|mp4|ico|webp)$ {\n"
            f"        valid_referers {referers};\n"
            "        if ($invalid_referer) {\n"
            "            return 403;\n"
            "        }\n"
            "    }\n"
        )
    
    def add_hotlink(self, referers: str) -> bool:
        """添加防盗链配置"""
        print("正在添加防盗链配置...")
        
        # 备份配置文件
        if not self.backup_config():
            return False
        
        lines = self.read_config()
        if not lines:
            return False
        
        # 查找SSL server块
        server_blocks = self.find_server_blocks(lines)
        ssl_server = self.find_ssl_server_block(lines, server_blocks)
        
        if not ssl_server:
            print("未找到SSL server块，无法添加防盗链配置", file=sys.stderr)
            return False
        
        start_line, end_line = ssl_server
        
        # 检查是否已存在防盗链配置
        existing_hotlink = self.find_hotlink_config(lines)
        if existing_hotlink:
            print("检测到已存在的防盗链配置，将先删除再添加")
            lines = self.remove_hotlink_internal(lines)
        
        # 查找插入位置（第一个location之前）
        insert_pos = start_line + 1
        for i in range(start_line + 1, end_line):
            if re.match(r'\s*location\s', lines[i]):
                insert_pos = i
                break
        
        # 生成防盗链配置
        hotlink_config = self.generate_hotlink_config(referers)
        
        # 插入配置
        new_lines = lines[:insert_pos] + [hotlink_config] + lines[insert_pos:]
        
        # 写入配置文件
        if self.write_config(new_lines):
            print("防盗链配置添加成功")
            return True
        else:
            print("防盗链配置添加失败，正在恢复备份...")
            self.restore_config()
            return False
    
    def remove_hotlink_internal(self, lines: List[str]) -> List[str]:
        """内部方法：从lines中删除防盗链配置"""
        existing_hotlink = self.find_hotlink_config(lines)
        if existing_hotlink:
            start_line, end_line = existing_hotlink
            return lines[:start_line] + lines[end_line + 1:]
        return lines
    
    def remove_hotlink(self) -> bool:
        """删除防盗链配置"""
        print("正在删除防盗链配置...")
        
        # 备份配置文件
        if not self.backup_config():
            return False
        
        lines = self.read_config()
        if not lines:
            return False
        
        # 查找并删除防盗链配置
        existing_hotlink = self.find_hotlink_config(lines)
        if not existing_hotlink:
            print("未找到防盗链配置")
            return True
        
        # 删除配置
        new_lines = self.remove_hotlink_internal(lines)
        
        # 写入配置文件
        if self.write_config(new_lines):
            print("防盗链配置删除成功")
            return True
        else:
            print("防盗链配置删除失败，正在恢复备份...")
            self.restore_config()
            return False
    
    def check_hotlink_status(self) -> bool:
        """检查防盗链配置状态"""
        lines = self.read_config()
        if not lines:
            return False
        
        existing_hotlink = self.find_hotlink_config(lines)
        if existing_hotlink:
            start_line, end_line = existing_hotlink
            print(f"防盗链配置已启用（第{start_line + 1}行到第{end_line + 1}行）")
            
            # 显示配置详情
            for i in range(start_line, end_line + 1):
                if i < len(lines):
                    line = lines[i].rstrip()
                    if line.strip():
                        print(f"  {line}")
            return True
        else:
            print("防盗链配置未启用")
            return False
    
    def fix_duplicate_servers(self) -> bool:
        """修复重复的server配置"""
        print("正在检查并修复重复的server配置...")
        
        # 查找所有配置文件
        vhost_dir = "/usr/local/nginx/conf/vhost"
        if not os.path.exists(vhost_dir):
            print(f"虚拟主机目录不存在: {vhost_dir}")
            return True
        
        fixed_files = []
        for filename in os.listdir(vhost_dir):
            if filename.endswith('.conf'):
                config_file = os.path.join(vhost_dir, filename)
                if self._fix_duplicate_servers_in_file(config_file):
                    fixed_files.append(filename)
        
        if fixed_files:
            print(f"已修复 {len(fixed_files)} 个配置文件中的重复server块")
            return True
        else:
            print("未发现重复的server配置")
            return True
    
    def _fix_duplicate_servers_in_file(self, config_file: str) -> bool:
        """修复单个文件中的重复server配置"""
        try:
            with open(config_file, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            # 使用字典来跟踪已见过的server_name
            seen_servers = {}
            new_lines = []
            i = 0
            
            while i < len(lines):
                line = lines[i]
                
                # 检查是否是server块开始
                if re.match(r'\s*server\s*{', line):
                    # 收集整个server块
                    server_block = [line]
                    server_name = ""
                    brace_count = 1
                    j = i + 1
                    
                    # 读取整个server块
                    while j < len(lines) and brace_count > 0:
                        server_block.append(lines[j])
                        if 'server_name' in lines[j] and not server_name:
                            # 提取server_name
                            name_match = re.search(r'server_name\s+([^;]+);', lines[j])
                            if name_match:
                                server_name = name_match.group(1).strip()
                        elif '{' in lines[j]:
                            brace_count += 1
                        elif '}' in lines[j]:
                            brace_count -= 1
                        j += 1
                    
                    # 如果server_name为空，使用整个块内容作为key
                    if not server_name:
                        server_name = ''.join(server_block)
                    
                    # 检查是否已存在相同的server_name
                    if server_name not in seen_servers:
                        seen_servers[server_name] = True
                        new_lines.extend(server_block)
                    else:
                        print(f"删除重复的server块: {server_name}")
                    
                    i = j
                else:
                    new_lines.append(line)
                    i += 1
            
            # 如果内容有变化，写回文件
            if new_lines != lines:
                with open(config_file, 'w', encoding='utf-8') as f:
                    f.writelines(new_lines)
                return True
            
            return False
            
        except Exception as e:
            print(f"修复文件 {config_file} 时出错: {e}")
            return False
    
    def validate_config(self) -> bool:
        """验证nginx配置语法"""
        try:
            import subprocess
            result = subprocess.run(['nginx', '-t'], 
                                  capture_output=True, 
                                  text=True, 
                                  timeout=10)
            if result.returncode == 0:
                print("nginx配置语法验证通过")
                return True
            else:
                print("nginx配置语法错误:")
                print(result.stderr)
                return False
        except Exception as e:
            print(f"无法验证nginx配置: {e}")
            return False

def main():
    if len(sys.argv) < 3:
        print("用法: hotlink-manager.py <conf_file> <action> [referers]")
        print("actions: add, remove, status, validate")
        sys.exit(1)
    
    conf_file = sys.argv[1]
    action = sys.argv[2]
    
    if not os.path.exists(conf_file):
        print(f"配置文件不存在: {conf_file}", file=sys.stderr)
        sys.exit(1)
    
    manager = HotlinkManager(conf_file)
    
    if action == "add":
        if len(sys.argv) < 4:
            print("添加防盗链需要指定referers参数", file=sys.stderr)
            sys.exit(1)
        referers = sys.argv[3]
        
        # 先修复重复配置
        manager.fix_duplicate_servers()
        
        success = manager.add_hotlink(referers)
        if success:
            manager.validate_config()
        sys.exit(0 if success else 1)
    
    elif action == "remove":
        success = manager.remove_hotlink()
        if success:
            manager.validate_config()
        sys.exit(0 if success else 1)
    
    elif action == "status":
        manager.check_hotlink_status()
        sys.exit(0)
    
    elif action == "validate":
        success = manager.validate_config()
        sys.exit(0 if success else 1)
    
    else:
        print(f"未知操作: {action}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main() 