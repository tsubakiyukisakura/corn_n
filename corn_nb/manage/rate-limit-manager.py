#!/usr/bin/env python3
"""
流量限制配置管理器
提供安全的流量限制配置添加、删除和查询功能
"""

import sys
import re
import os
import subprocess
from typing import List, Tuple, Optional

class RateLimitManager:
    def __init__(self, conf_file: str):
        self.conf_file = conf_file
        self.backup_file = f"{conf_file}.ratelimit.bak"
        self.rate_limit_marker = "# 流量限制配置"
        self.nginx_main_conf = "/usr/local/nginx/conf/nginx.conf"
        
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
    
    def read_main_config(self) -> List[str]:
        """读取nginx主配置文件"""
        try:
            with open(self.nginx_main_conf, 'r', encoding='utf-8') as f:
                return f.readlines()
        except Exception as e:
            print(f"读取nginx主配置文件失败: {e}", file=sys.stderr)
            return []
    
    def write_main_config(self, lines: List[str]) -> bool:
        """写入nginx主配置文件"""
        try:
            with open(self.nginx_main_conf, 'w', encoding='utf-8') as f:
                f.writelines(lines)
            return True
        except Exception as e:
            print(f"写入nginx主配置文件失败: {e}", file=sys.stderr)
            return False
    
    def find_rate_limit_config(self, lines: List[str]) -> Optional[Tuple[int, int]]:
        """查找现有的流量限制配置"""
        start_line = None
        end_line = None
        
        for i, line in enumerate(lines):
            if self.rate_limit_marker in line:
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
    
    def check_main_config_zones(self) -> bool:
        """检查主配置文件中是否已定义限速区域"""
        lines = self.read_main_config()
        if not lines:
            return False
        
        has_req_zone = any('limit_req_zone' in line for line in lines)
        has_conn_zone = any('limit_conn_zone' in line for line in lines)
        
        return has_req_zone and has_conn_zone
    
    def add_zones_to_main_config(self, req_limit: int, conn_limit: int) -> bool:
        """在主配置文件中添加限速区域定义"""
        lines = self.read_main_config()
        if not lines:
            return False
        
        # 检查是否已存在
        if self.check_main_config_zones():
            print("限速区域已存在于主配置文件中")
            return True
        
        # 查找http块
        http_start = None
        http_end = None
        brace_count = 0
        
        for i, line in enumerate(lines):
            if re.match(r'\s*http\s*{', line):
                http_start = i
                brace_count = 1
            elif '{' in line and http_start is not None:
                brace_count += 1
            elif '}' in line and http_start is not None:
                brace_count -= 1
                if brace_count == 0:
                    http_end = i
                    break
        
        if http_start is None or http_end is None:
            print("未找到http块，无法添加限速区域", file=sys.stderr)
            return False
        
        # 在http块开始后添加区域定义
        zone_config = (
            f"    # 流量限制区域定义\n"
            f"    limit_req_zone $binary_remote_addr zone=req_limit_per_ip:10m rate={req_limit}r/s;\n"
            f"    limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;\n"
        )
        
        new_lines = lines[:http_start + 1] + [zone_config] + lines[http_start + 1:]
        
        return self.write_main_config(new_lines)
    
    def generate_rate_limit_config(self, req_limit: int, conn_limit: int, body_size_limit: int = 1024, skip_body_size: bool = False) -> str:
        """生成流量限制配置"""
        # 根据限制级别设置合适的burst值
        if req_limit <= 2:
            burst = 3  # 严格限制
        elif req_limit <= 5:
            burst = 10  # 中等限制
        else:
            burst = 20  # 基础限制
        
        config_lines = [f"    {self.rate_limit_marker}"]
        
        # 只有在不跳过时才添加client_max_body_size
        if not skip_body_size:
            config_lines.append(f"    client_max_body_size {body_size_limit}k;")
        
        config_lines.extend([
            f"    limit_req zone=req_limit_per_ip burst={burst} nodelay;",
            f"    limit_conn conn_limit_per_ip {conn_limit};",
            f"    limit_req_status 429;",
            f"    limit_conn_status 429;"
        ])
        
        return "\n".join(config_lines) + "\n"
    
    def add_rate_limit(self, req_limit: int, conn_limit: int, body_size_limit: int = 1024) -> bool:
        """添加流量限制配置"""
        print("正在添加流量限制配置...")
        
        # 备份配置文件
        if not self.backup_config():
            return False
        
        # 确保主配置文件中有区域定义
        if not self.add_zones_to_main_config(req_limit, conn_limit):
            print("添加限速区域失败", file=sys.stderr)
            return False
        
        lines = self.read_config()
        if not lines:
            return False
        
        # 检查是否已存在流量限制配置
        existing_config = self.find_rate_limit_config(lines)
        if existing_config:
            print("检测到已存在的流量限制配置，将先删除再添加")
            lines = self.remove_rate_limit_internal(lines)
        
        # 查找所有server块并添加流量限制配置
        new_lines = lines.copy()
        server_blocks = []
        brace_count = 0
        server_start = None
        
        for i, line in enumerate(lines):
            if re.match(r'\s*server\s*{', line):
                server_start = i
                brace_count = 1
            elif '{' in line and server_start is not None:
                brace_count += 1
            elif '}' in line and server_start is not None:
                brace_count -= 1
                if brace_count == 0:
                    server_blocks.append((server_start, i))
                    server_start = None
        
        if not server_blocks:
            print("未找到server块，无法添加流量限制配置", file=sys.stderr)
            return False
        
        # 为每个server块添加流量限制配置
        offset = 0
        for start, end in server_blocks:
            # 检查server块中是否已存在client_max_body_size
            has_body_size = any('client_max_body_size' in line for line in lines[start:end])
            
            # 查找插入位置（server_name之后）
            insert_pos = start + 1
            for i in range(start + 1, end):
                if 'server_name' in lines[i]:
                    insert_pos = i + 1
                    break
            
            # 生成流量限制配置（如果已存在client_max_body_size则跳过）
            rate_limit_config = self.generate_rate_limit_config(req_limit, conn_limit, body_size_limit, skip_body_size=has_body_size)
            
            # 插入配置（考虑之前插入的偏移量）
            actual_insert_pos = insert_pos + offset
            new_lines = new_lines[:actual_insert_pos] + [rate_limit_config] + new_lines[actual_insert_pos:]
            offset += len(rate_limit_config.split('\n'))
        
        # 写入配置文件
        if self.write_config(new_lines):
            print("流量限制配置添加成功")
            return True
        else:
            print("流量限制配置添加失败，正在恢复备份...")
            self.restore_config()
            return False
    
    def remove_rate_limit_internal(self, lines: List[str]) -> List[str]:
        """内部方法：从lines中删除流量限制配置"""
        new_lines = lines.copy()
        removed_count = 0
        
        # 查找并删除所有流量限制配置
        i = 0
        while i < len(new_lines):
            if self.rate_limit_marker in new_lines[i]:
                # 找到流量限制配置的开始
                start_line = i
                # 查找对应的结束位置
                brace_count = 0
                end_line = start_line
                
                for j in range(start_line, len(new_lines)):
                    if '{' in new_lines[j]:
                        brace_count += 1
                    elif '}' in new_lines[j]:
                        brace_count -= 1
                        if brace_count == 0:
                            end_line = j
                            break
                
                # 删除这个配置块
                new_lines = new_lines[:start_line] + new_lines[end_line + 1:]
                removed_count += 1
                # 不增加i，因为删除后需要重新检查当前位置
            else:
                i += 1
        
        if removed_count > 0:
            print(f"删除了 {removed_count} 个流量限制配置块")
        
        return new_lines
    
    def remove_rate_limit(self) -> bool:
        """删除流量限制配置"""
        print("正在删除流量限制配置...")
        
        # 备份配置文件
        if not self.backup_config():
            return False
        
        lines = self.read_config()
        if not lines:
            return False
        
        # 查找并删除流量限制配置
        existing_config = self.find_rate_limit_config(lines)
        if not existing_config:
            print("未找到流量限制配置")
            return True
        
        # 删除配置
        new_lines = self.remove_rate_limit_internal(lines)
        
        # 写入配置文件
        if self.write_config(new_lines):
            print("流量限制配置删除成功")
            return True
        else:
            print("流量限制配置删除失败，正在恢复备份...")
            self.restore_config()
            return False
    
    def check_rate_limit_status(self) -> bool:
        """检查流量限制配置状态"""
        lines = self.read_config()
        if not lines:
            return False
        
        existing_config = self.find_rate_limit_config(lines)
        if existing_config:
            start_line, end_line = existing_config
            print(f"流量限制配置已启用（第{start_line + 1}行到第{end_line + 1}行）")
            
            # 显示配置详情
            for i in range(start_line, end_line + 1):
                if i < len(lines):
                    line = lines[i].rstrip()
                    if line.strip():
                        print(f"  {line}")
            
            # 检查主配置文件中的区域定义
            if self.check_main_config_zones():
                print("✅ 主配置文件中已定义限速区域")
            else:
                print("⚠️  主配置文件中未找到限速区域定义")
            
            return True
        else:
            print("流量限制配置未启用")
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
            
            # 使用字典来跟踪已见过的server配置（包括端口）
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
                    server_port = ""
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
                        elif 'listen' in lines[j] and not server_port:
                            # 提取端口信息
                            port_match = re.search(r'listen\s+(\d+)(?:\s+ssl)?;', lines[j])
                            if port_match:
                                server_port = port_match.group(1)
                        elif '{' in lines[j]:
                            brace_count += 1
                        elif '}' in lines[j]:
                            brace_count -= 1
                        j += 1
                    
                    # 创建唯一的server标识（server_name + port）
                    server_key = f"{server_name}:{server_port}" if server_name and server_port else ''.join(server_block)
                    
                    # 检查是否已存在相同的server配置
                    if server_key not in seen_servers:
                        seen_servers[server_key] = True
                        new_lines.extend(server_block)
                    else:
                        print(f"删除重复的server块: {server_name}:{server_port}")
                    
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
    
    def fix_duplicate_directives(self) -> bool:
        """修复重复的nginx指令"""
        print("正在检查并修复重复的nginx指令...")
        
        lines = self.read_config()
        if not lines:
            return False
        
        # 查找并修复重复的client_max_body_size指令
        new_lines = []
        in_server = False
        seen_body_size = False
        
        for line in lines:
            if re.match(r'\s*server\s*{', line):
                in_server = True
                seen_body_size = False
                new_lines.append(line)
            elif re.match(r'\s*}', line) and in_server:
                in_server = False
                new_lines.append(line)
            elif in_server and 'client_max_body_size' in line:
                if not seen_body_size:
                    new_lines.append(line)
                    seen_body_size = True
                else:
                    print(f"删除重复的client_max_body_size指令: {line.strip()}")
            else:
                new_lines.append(line)
        
        # 如果内容有变化，写回文件
        if new_lines != lines:
            return self.write_config(new_lines)
        
        return True
    
    def validate_config(self) -> bool:
        """验证nginx配置语法"""
        try:
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
                
                # 如果是因为重复指令导致的错误，尝试修复
                if "duplicate" in result.stderr:
                    print("检测到重复指令，正在尝试修复...")
                    if self.fix_duplicate_directives():
                        print("重复指令修复完成，重新验证配置...")
                        return self.validate_config()
                
                return False
        except Exception as e:
            print(f"无法验证nginx配置: {e}")
            return False

def main():
    if len(sys.argv) < 3:
        print("用法: rate-limit-manager.py <conf_file> <action> [req_limit] [conn_limit]")
        print("actions: add, remove, status, validate")
        sys.exit(1)
    
    conf_file = sys.argv[1]
    action = sys.argv[2]
    
    if not os.path.exists(conf_file):
        print(f"配置文件不存在: {conf_file}", file=sys.stderr)
        sys.exit(1)
    
    manager = RateLimitManager(conf_file)
    
    if action == "add":
        if len(sys.argv) < 5:
            print("添加流量限制需要指定req_limit和conn_limit参数", file=sys.stderr)
            sys.exit(1)
        req_limit = int(sys.argv[3])
        conn_limit = int(sys.argv[4])
        body_size_limit = int(sys.argv[5]) if len(sys.argv) > 5 else 1024
        
        # 先修复重复配置
        manager.fix_duplicate_servers()
        
        success = manager.add_rate_limit(req_limit, conn_limit, body_size_limit)
        if success:
            # 验证配置（会自动修复重复指令）
            manager.validate_config()
        sys.exit(0 if success else 1)
    
    elif action == "remove":
        success = manager.remove_rate_limit()
        if success:
            manager.validate_config()
        sys.exit(0 if success else 1)
    
    elif action == "status":
        manager.check_rate_limit_status()
        sys.exit(0)
    
    elif action == "validate":
        success = manager.validate_config()
        sys.exit(0 if success else 1)
    
    else:
        print(f"未知操作: {action}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main() 