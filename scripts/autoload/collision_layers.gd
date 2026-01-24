##############################################################################
# CollisionLayers - 碰撞层统一管理
#
# 功能说明：
# 1. 定义所有碰撞层的常量
# 2. 提供给所有脚本使用，避免魔法数字
# 3. 统一管理碰撞规则
#
# 使用方式：
#   collision_layer = CollisionLayers.PLAYER
#   collision_mask = CollisionLayers.ENEMY | CollisionLayers.PICKUP
##############################################################################
extends Node

## 碰撞层常量定义
## 单位：层级索引
## 作用：统一管理所有碰撞层，避免硬编码数字
## 调整建议：新增层级时在此添加常量

## 玩家层
## 碰撞对象：敌人、敌人投射物、拾取物、墙、商店门、工坊门
const PLAYER: int = 1

## 敌人层
## 碰撞对象：玩家、玩家投射物、墙
const ENEMY: int = 2

## 玩家投射物/武器攻击范围层
## 碰撞对象：敌人、墙
const PLAYER_PROJECTILE: int = 3

## 敌人投射物/攻击范围层
## 碰撞对象：玩家、墙
const ENEMY_PROJECTILE: int = 4

## 拾取物层（金币、矿石、血瓶）
## 碰撞对象：玩家、墙
const PICKUP: int = 5

## 墙/障碍物层
## 碰撞对象：所有
const WALL: int = 6

## 商店门碰撞体层
## 碰撞对象：玩家
const SHOP_DOOR: int = 7

## 工坊门碰撞体层
## 碰撞对象：玩家
const FORGE_DOOR: int = 8

## 获取层级掩码值
## 作用：将层级索引转换为位掩码值
## 参数：
##   layer_index - 层级索引（1-32）
## 返回：
##   位掩码值（用于设置collision_layer或collision_mask）
## 示例：
##   var mask = CollisionLayers.get_layer_mask(CollisionLayers.PLAYER)  # 返回 1
##   var combined_mask = CollisionLayers.get_layer_mask(CollisionLayers.ENEMY) | CollisionLayers.get_layer_mask(CollisionLayers.PICKUP)
func get_layer_mask(layer_index: int) -> int:
	return 1 << (layer_index - 1)

## 检查层级是否在掩码中
## 作用：判断某个层级是否包含在碰撞掩码中
## 参数：
##   mask - 碰撞掩码值
##   layer_index - 要检查的层级索引
## 返回：
##   true表示包含，false表示不包含
## 示例：
##   var mask = 0b00000011  # 包含层1和层2
##   CollisionLayers.has_layer(mask, CollisionLayers.PLAYER)  # 返回 true
##   CollisionLayers.has_layer(mask, CollisionLayers.PICKUP)  # 返回 false
func has_layer(mask: int, layer_index: int) -> bool:
	var layer_bit: int = get_layer_mask(layer_index)
	return (mask & layer_bit) != 0

## 组合多个层级为掩码
## 作用：将多个层级索引组合为一个掩码值
## 参数：
##   layers - 层级索引数组
## 返回：
##   组合后的掩码值
## 示例：
##   var mask = CollisionLayers.combine_layers([CollisionLayers.ENEMY, CollisionLayers.PICKUP])
func combine_layers(layers: Array[int]) -> int:
	var result: int = 0
	for layer_index: int in layers:
		result |= get_layer_mask(layer_index)
	return result
