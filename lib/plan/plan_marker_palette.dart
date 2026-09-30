/// 计划标记配色：舞 DDL / 随舞事件 / 团内检查三类
/// 各一色，是时间轴竖线、图例、日历圆点、点日下栏与日程列表行首图标的
/// 唯一取色来源。颜色只表达类型，逾期 / 达成等状态不进入这张表。
library;

import 'package:flutter/material.dart';

import 'plan_mark_kind.dart';

/// 舞 DDL 标记色（紫）。
const Color kPlanMarkDdlColor = Color(0xFF6750A4);

/// 随舞事件标记色（橙）。
const Color kPlanMarkSocialColor = Color(0xFFE8710A);

/// 团内检查标记色（青绿）。
const Color kPlanMarkTeamCheckColor = Color(0xFF00695C);

/// 三类标记的呈现取值（颜色 / 图例名 / 键名后缀）：唯一一处穷尽声明，
/// 新增类型只改这一张表。
({Color color, String label, String slug}) _planMarkStyle(PlanMarkKind kind) =>
    switch (kind) {
      PlanMarkKind.ddl => (
        color: kPlanMarkDdlColor,
        label: '舞 DDL',
        slug: 'ddl',
      ),
      PlanMarkKind.social => (
        color: kPlanMarkSocialColor,
        label: '随舞事件',
        slug: 'social',
      ),
      PlanMarkKind.teamCheck => (
        color: kPlanMarkTeamCheckColor,
        label: '团内检查',
        slug: 'teamcheck',
      ),
    };

Color planMarkColor(PlanMarkKind kind) => _planMarkStyle(kind).color;

String planMarkLabel(PlanMarkKind kind) => _planMarkStyle(kind).label;

/// 标记类型的键名后缀（页面键与图例键共用，全小写无驼峰）。
String planMarkSlug(PlanMarkKind kind) => _planMarkStyle(kind).slug;

/// 时间轴分型竖线键：舞 DDL 沿用 `plan_timeline_marker_<日>`，其余带类型后缀。
String planTimelineMarkerKey(PlanMarkKind kind, String dayKey) =>
    kind == PlanMarkKind.ddl
    ? 'plan_timeline_marker_$dayKey'
    : 'plan_timeline_marker_${planMarkSlug(kind)}_$dayKey';
