##############################################################################
# CollisionLayers - 碰撞层统一管理
#
# 设计目的：
# - 统一定义碰撞层编号
# - 提供mask计算与组合工具
##############################################################################
extends Node

## 玩家层
const PLAYER: int = 1

## 敌人层
const ENEMY: int = 2

## 玩家投射物层
const PLAYER_PROJECTILE: int = 3

## 敌人投射物层
const ENEMY_PROJECTILE: int = 4

## 拾取物层（金币/矿石/血瓶）
const PICKUP: int = 5

## 墙体/障碍层
const WALL: int = 6

## 商店门碰撞层
const SHOP_DOOR: int = 7

## 工坊门碰撞层
const FORGE_DOOR: int = 8

## 获取层mask
func get_layer_mask(layer_index: int) -> int:
	return 1 << (layer_index - 1)

## 判断mask是否包含某层
func has_layer(mask: int, layer_index: int) -> bool:
	var layer_bit: int = get_layer_mask(layer_index)
	return (mask & layer_bit) != 0

## 合并多个层mask
func combine_layers(layers: Array[int]) -> int:
	var result: int = 0
	for layer_index: int in layers:
		result |= get_layer_mask(layer_index)
	return result
