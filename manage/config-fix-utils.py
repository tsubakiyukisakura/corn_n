#!/usr/bin/env python3
"""
nginx配置修复工具
提供通用的配置修复功能，包括重复server块清理等
"""

import os
import re
from typing import List, Dict, Tuple

class ConfigFixUtils:
    """nginx配置修复工具类"""
    
    @staticmethod
    def fix_duplicate_servers(vhost_dir: str = "/usr/local/nginx/conf/vhost") -> Dict[str, bool]:
        """
        修复重复的server配置
        
        Args:
            vhost_dir: 虚拟主机配置目录
            
        Returns:
            Dict[str, bool]: 修复结果，key为文件名，value为是否修复成功
        """
        results = {}
        
        if not os.path.exists(vhost_dir):
            print(f"虚拟主机目录不存在: {vhost_dir}")
            return results
        
        print("正在检查并修复重复的server配置...")
        
        for filename in os.listdir(vhost_dir):
            if filename.endswith('.conf'):
                config_file = os.path.join(vhost_dir, filename)
                results[filename] = ConfigFixUtils._fix_duplicate_servers_in_file(config_file)
        
        fixed_count = sum(1 for success in results.values() if success)
        if fixed_count > 0:
            print(f"已修复 {fixed_count} 个配置文件中的重复server块")
        else:
            print("未发现重复的server配置")
        
        return results
    
    @staticmethod
    def _fix_duplicate_servers_in_file(config_file: str) -> bool:
        """
        修复单个文件中的重复server配置
        
        Args:
            config_file: 配置文件路径
            
        Returns:
            bool: 是否修复成功
        """
        try:
            with open(config_file, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            # 使用字典来跟踪已见过的server配置（包括端口）
            seen_servers = {}
            new_lines = []
            i = 0
            removed_count = 0
            
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
                        removed_count += 1
                    
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
    
    @staticmethod
    def check_nginx_config() -> bool:
        """
        检查nginx配置语法
        
        Returns:
            bool: 配置是否正确
        """
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
    
    @staticmethod
    def backup_config(config_file: str) -> str:
        """
        备份配置文件
        
        Args:
            config_file: 配置文件路径
            
        Returns:
            str: 备份文件路径
        """
        try:
            backup_file = f"{config_file}.backup.{int(os.time.time())}"
            with open(config_file, 'r', encoding='utf-8') as src:
                with open(backup_file, 'w', encoding='utf-8') as dst:
                    dst.write(src.read())
            print(f"已备份配置文件到: {backup_file}")
            return backup_file
        except Exception as e:
            print(f"备份配置文件失败: {e}")
            return ""
    
    @staticmethod
    def restore_config(backup_file: str, config_file: str) -> bool:
        """
        恢复配置文件
        
        Args:
            backup_file: 备份文件路径
            config_file: 目标配置文件路径
            
        Returns:
            bool: 是否恢复成功
        """
        try:
            if os.path.exists(backup_file):
                with open(backup_file, 'r', encoding='utf-8') as src:
                    with open(config_file, 'w', encoding='utf-8') as dst:
                        dst.write(src.read())
                print(f"已恢复配置文件: {config_file}")
                return True
        except Exception as e:
            print(f"恢复配置文件失败: {e}")
        return False

def main():
    """主函数，用于独立运行配置修复"""
    import sys
    
    if len(sys.argv) > 1 and sys.argv[1] == "fix":
        # 修复重复配置
        results = ConfigFixUtils.fix_duplicate_servers()
        if any(results.values()):
            # 验证配置
            ConfigFixUtils.check_nginx_config()
        sys.exit(0)
    elif len(sys.argv) > 1 and sys.argv[1] == "check":
        # 检查配置
        success = ConfigFixUtils.check_nginx_config()
        sys.exit(0 if success else 1)
    else:
        print("用法: config-fix-utils.py [fix|check]")
        print("  fix  - 修复重复的server配置")
        print("  check - 检查nginx配置语法")
        sys.exit(1)

if __name__ == "__main__":
    main() 