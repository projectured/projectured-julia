# Architecture review: Layout, style, theme, appearance, graphics

Commit 3a9b4fae4. Reviewer area key: layout-style.

## Scope

Paths: `source/platform/{layout,style,appearance,primitive,graphics,screen,plot}`, `source/platform/widget/{WidgetStyle.jl,WidgetTheme.jl,WidgetDecoration.jl}`, the 18 theme files of the domains, `source/platform/task/TaskTheme.jl`, `source/adapter/tulip`. The area holds about 21 500 lines.

**Read in full (about 3 400 lines):** `layout/LayoutDocument.jl` (1268), `layout/LayoutList.jl` (375), `style/Theme.jl` (412), `widget/WidgetTheme.jl` (302), `widget/WidgetStyle.jl` (466), `widget/WidgetDecoration.jl` (166), `appearance/AppearanceManagingProjection.jl` (187), `plot/PlotStyle.jl` (103), `graphics/EventPosition.jl` (45), `graphics/GraphicsTheme.jl`, `task/TaskTheme.jl`, `json/JsonTheme.jl`, `layout/ConstraintSolver.jl`.

**Read in ranges (about 3 300 lines):** `layout/LayoutToGraphics.jl` lines 1–755, 1010–1530, 1620–1919, 2191–2250, 2386–2475, 2595–2700, 2782–2800, 2945–2972, 3018–3086 (about 1 950 of 3 086); `graphics/GraphicsDocument.jl` 940–1306; `widget/WidgetToGraphics.jl` 1–330; `kernel/projection/PrinterContext.jl` 30–130 and 260–400; `settingsmanaging/SettingsManagingProjection.jl`; `appearance/AppearanceWrapper.jl` 40–98; `screen/ScreenToScreen.jl` 476–524; `screen/WindowPlacement.jl` 100–150; `screen/WindowManaging.jl` 262–300; `layout/GridList.jl` 1–75 and 429–477.

**Sampled by outline and grep:** `style/Appearance.jl`, `appearance/AppearanceToWidget.jl`, `layout/GridColumnList.jl`, `screen/ScreenDocument.jl`, `graphics/PointerShape.jl`, `graphics/ReferenceBox.jl`, `primitive/PrimitiveDocument.jl`, `ChartTheme.jl`, `GraphTheme.jl`, `ChartDocument.jl` (the style), `SequenceChartDocument.jl` (the style), the three backends (the canvas walk and the type cases only), the settings slice (the outline).

**Not read in code:** `plot/PlotGeometry.jl` and `adapter/tulip/TulipConstraintSolver.jl` (the package documents and the outlines only), `style/TrueType.jl`, `style/Image.jl`, `style/FontFace.jl`.

**Documents read:** `concepts.md`, `architecture-decisions.md`, the index of `architecture-invariants.md` and PAR-PER-EDITOR-STATE, `layout-rules.md`, `spacing-rules.md`, `type-rules.md`, and the package documents of layout, style, appearance, graphics, plot, primitive, screen (first part), settings (first part) and collection (first part).

## State

The rules of this area are stronger than most of the code that follows them. `layout-rules.md` states one size rule for both axes, `spacing-rules.md` derives each space from a rule about what a person sees, and `type-rules.md` gives one table of font roles. The colour chain and the font chain are clean: a guard keeps literal colours and fonts out of the code, and I found 7 literal `StyleColor(` values outside the style slice and the theme files, 6 of them in a debug projection. All 41 themes use one macro, `@theme`. One allocator, `allocate_axis`, serves the stacks, the grid and the split pane.

The main weakness is that the layout slice keeps the rule in three of its nine layouts only (corrected by the check: five; `LayoutConstraint` forwards the range and `ScrollLayout` gives its center the range less the bands; see the check of LS-3). The row, the column and the grid follow the size protocol. The stack, the flow, the constraint layout and the anchored layout each have a local rule. The slice also holds five readers that route an event to a child, each with another set of abilities, and a second printer of each layout for a lazy list, which lacks what the first printer has. So a feature works in a column of a vector and fails in a column of a list or in a stack.

The second weakness is on the appearance side. The appearance and the settings are the same mechanism written twice, from the macro to the tab. A length has no shared role, as a colour and a font have. A per-instance style has three unrelated shapes.

The graphics slice is small and sound in its model, but each consumer of a canvas repeats the walk of its elements and the case over the kinds of primitive. A fourth backend is planned, and it would repeat both again.

## Inventory

### I1. The layout kinds

`LayoutToGraphics` ([LayoutToGraphics.jl:3060](../../../source/platform/layout/LayoutToGraphics.jl#L3060)) is the dispatch of the nine kinds. "Uses" counts constructor calls in `source/` outside the layout slice.

| Document | Printer | Children | Reader | Uses |
| --- | --- | --- | --- | --- |
| `HorizontalLayout` | `_hl_build` [:1077](../../../source/platform/layout/LayoutToGraphics.jl#L1077), or `_print_layout_list` [LayoutList.jl:121](../../../source/platform/layout/LayoutList.jl#L121) | vector or list | `_route_layout_event`, or the list reader | 80 |
| `VerticalLayout` | `_vl_build` [:1378](../../../source/platform/layout/LayoutToGraphics.jl#L1378), or `_print_layout_list` | vector or list | the same | 113 |
| `GridLayout` (and `FormLayout`, a constructor) | [:1760](../../../source/platform/layout/LayoutToGraphics.jl#L1760), or `_print_grid_list` [GridList.jl:100](../../../source/platform/layout/GridList.jl#L100), or `GridColumnList.jl` | vector, list of rows, list of rows of a list of columns | `_route_layout_event`, or the grid list reader | 45 + 1 |
| `FlowLayout` | [:2191](../../../source/platform/layout/LayoutToGraphics.jl#L2191) | vector | `_route_layout_event` | 5 |
| `StackLayout` | [:2443](../../../source/platform/layout/LayoutToGraphics.jl#L2443) | vector | `_route_stack_event` | 1 |
| `ConstraintLayout` | `_cl_build` [:2595](../../../source/platform/layout/LayoutToGraphics.jl#L2595) | vector | `_route_stack_event` | 0 |
| `AnchoredLayout` | `_al_build` [:2782](../../../source/platform/layout/LayoutToGraphics.jl#L2782) | content + vector | `_route_stack_event` | 0 |
| `ScrollLayout` | `_scroll_layout_build` [:2945](../../../source/platform/layout/LayoutToGraphics.jl#L2945) | nine fields | its own reader [:3024](../../../source/platform/layout/LayoutToGraphics.jl#L3024) | 2 |
| `LayoutConstraint` | forwards one child [:612](../../../source/platform/layout/LayoutToGraphics.jl#L612) | one child | forwards | 57 |

### I2. Layout × size protocol

The protocol is one: a range `(minimum, maximum)` for each axis in `PrinterContext`, a `space` tuple, and the visible extent as a property ([PrinterContext.jl:65](../../../source/kernel/projection/PrinterContext.jl#L65), [LayoutToGraphics.jl:1339](../../../source/platform/layout/LayoutToGraphics.jl#L1339)). The matrix shows which layout applies it.

| Layout | Divides the edge of its range | `Fixed` child | `Fill` / `Relative` child | `Content` child gets a bounded range | Placement minimum and maximum | Cuts | Space of the slot |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Row, column (vector) | yes [:1101](../../../source/platform/layout/LayoutToGraphics.jl#L1101) | yes | yes | yes, `_main_context` [:1253](../../../source/platform/layout/LayoutToGraphics.jl#L1253) | yes | by `LayoutConstraint` | by side |
| Row, column (list) | cross axis only | yes | error for the default of the layout [LayoutList.jl:66](../../../source/platform/layout/LayoutList.jl#L66), not read on a child | main axis free | partly | no | by side |
| Grid (vector) | yes, both axes [:1791](../../../source/platform/layout/LayoutToGraphics.jl#L1791) | yes | yes | yes | yes | sized column and row | by side |
| Grid (list) | width only | columns and rows | columns only; a row gives an error [GridList.jl:80](../../../source/platform/layout/GridList.jl#L80) | no `Content` column | partly | yes | — |
| Flow | reads the maximum width to break lines | cut by the wrapper, not offered | no | no: free on both axes [:2205](../../../source/platform/layout/LayoutToGraphics.jl#L2205) | no | no | around itself |
| Stack | no | cut by the wrapper, not offered | no | no: free on both axes [:2459](../../../source/platform/layout/LayoutToGraphics.jl#L2459) | no | no | whole to each child |
| Constraint | no: its own `bounding_width`, `bounding_height` [:2611](../../../source/platform/layout/LayoutToGraphics.jl#L2611) | by a relation | by a relation | measure pass with a free range | by a relation | no | around itself |
| Anchored | no: its own `bounding_width`, `bounding_height` [:2810](../../../source/platform/layout/LayoutToGraphics.jl#L2810) | no | no | each child gets the range of the layout itself | no | no | content only |
| Scroll layout | center: the range less the bands; edges free | no | no | no | no | no | — |
| `WidgetComposite` (widget slice, overlapping children) | — | yes | yes | yes, `make_cross_axis_context` on both axes [WidgetToGraphics.jl:4319](../../../source/platform/widget/WidgetToGraphics.jl#L4319) | yes | yes | — |

### I3. The readers that give an event to a placed child

| Reader | Used by | Click | Scroll | Move, with the leave of the old child | Dwell at the point | Down and up at the point | Tab, offered to the child first | Outward gesture (`read_container_gesture`) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `_route_layout_event` [:480](../../../source/platform/layout/LayoutToGraphics.jl#L480) | row, column, grid, flow (vector) | yes | yes | yes | yes | yes | yes | yes |
| `_route_stack_event` [:2417](../../../source/platform/layout/LayoutToGraphics.jl#L2417) | stack, constraint, anchored | yes, topmost first | yes | yes | no: goes to the selected child, point not moved | no: the same | yes, inside `_layout_tab` | no |
| list reader [LayoutList.jl:329](../../../source/platform/layout/LayoutList.jl#L329) | row, column (list) | yes | yes | no leave | yes | yes | no Tab walk | yes |
| grid list reader [GridList.jl:435](../../../source/platform/layout/GridList.jl#L435) | grid (list) | yes | yes | no leave | yes | yes | no Tab walk | yes |
| scroll layout reader [:3024](../../../source/platform/layout/LayoutToGraphics.jl#L3024) | scroll layout | yes | yes | yes | yes | yes | no Tab walk | yes |

Each reader also builds the moved event by hand for some event types (`MouseClick(evt.button, x, y, …)`), although `shift_event_position` ([EventPosition.jl:17](../../../source/platform/graphics/EventPosition.jl#L17)) moves any event: 6 places in `LayoutToGraphics.jl`, 4 in `LayoutList.jl` ([:357](../../../source/platform/layout/LayoutList.jl#L357)), 34 in `WidgetToGraphics.jl` (counts corrected by the check: the constructors `MouseClick(evt.button`, `MouseDown(evt.button`, `MouseUp(evt.button` and `MouseMove(…, evt.buttons`).

### I4. A layout of a vector against a layout of a list

| Ability | Row, column of a vector | Row, column of a list | Grid of a vector | Grid of a list |
| --- | --- | --- | --- | --- |
| Ring around a child selected as a whole | yes [:1198](../../../source/platform/layout/LayoutToGraphics.jl#L1198) | no | yes [:2031](../../../source/platform/layout/LayoutToGraphics.jl#L2031) | no |
| Backward reference map | yes [:1207](../../../source/platform/layout/LayoutToGraphics.jl#L1207) | `nothing` [LayoutList.jl:323](../../../source/platform/layout/LayoutList.jl#L323) | yes | `nothing` [GridList.jl:429](../../../source/platform/layout/GridList.jl#L429) |
| Tab walk to the next sibling | yes | no | yes | no |
| Leave of the child that the pointer was on | yes | no | yes | no |
| `:baseline` alignment | row: yes [:1046](../../../source/platform/layout/LayoutToGraphics.jl#L1046) | no [LayoutList.jl:239](../../../source/platform/layout/LayoutList.jl#L239) | — | — |
| `column_span`, `row_gaps`, `row_policies` | — | — | yes | no (the constructor takes none, [LayoutDocument.jl:398](../../../source/platform/layout/LayoutDocument.jl#L398)) |
| Flow, stack, constraint, anchored | vector only | — | — | — |

`isa ListNode` branches stand in 26 files of `source/`, among them `WidgetTableParts.jl` (28), `WidgetToGraphics.jl` (13), `GridColumnList.jl` (9) and `SdlBackend.jl` (7).

### I5. Where a visual value comes from

```
colour:  Palette ramp (RadixPalette.jl …, registry Palette.jl:111)
           -> role of ColorTheme (63 roles, one theme per mode and contrast)
           -> field of a theme (ColorRole(:border); WidgetTheme has 36 such fields)
           -> scaled theme (computed cell, scale_theme_value)
           -> style field of a projection (UntrackedCell, read with no edge)
           -> [widgets only] WidgetStyle of one widget document, by the name of the field
           -> GraphicsRect.color
font:    family of FontTheme -> role of FontTheme (FontStep) -> field of a theme (FontRole)
           -> scaled theme (font scale) -> style field -> GraphicsText.font
length:  literal in the field of a theme (Spacing(8), Radius(6), LineWidth(2))
           -> scaled theme (one of five scales by the type) -> style field -> geometry
```

Counts: 41 `@theme` declarations; more than 800 `get_<name>_style(` calls that give a style to a projection; 375 `_themed(` derivations in `WidgetToGraphics.jl`. Literal lengths in theme files: 13 `Radius(n)` in four values, 16 `LineWidth(n)` in three values, 55 scalar `Spacing(n)` (`Spacing(8)` 15 times), in 16 theme files (corrected by the check). Outside the theme files: 0 literal `gap`, `padding` or `margin` in `source/domain` and `source/adapter`.

Side entries into the chain: the background of a window ([ScreenDocument.jl:35](../../../source/platform/screen/ScreenDocument.jl#L35), [AppearanceWrapper.jl:62](../../../source/platform/appearance/AppearanceWrapper.jl#L62)); `default_color_cycle()` ([PlotStyle.jl:27](../../../source/platform/plot/PlotStyle.jl#L27)); the pixel sizes of `SequenceChartStyle` ([SequenceChartDocument.jl:407](../../../source/domain/sequencechart/SequenceChartDocument.jl#L407)).

### I6. A style of one document, over the theme

| Shape | Where | Overrides | Match to the theme |
| --- | --- | --- | --- |
| `WidgetStyle` and 23 more types | [WidgetStyle.jl:25](../../../source/platform/widget/WidgetStyle.jl#L25) | colours only | by the name of the style field of the projection, `hasfield` [WidgetToGraphics.jl:58](../../../source/platform/widget/WidgetToGraphics.jl#L58) |
| the insets of a widget (`margin`, `border`, `padding` fields of the widget) | [WidgetToGraphics.jl:129](../../../source/platform/widget/WidgetToGraphics.jl#L129) | three insets | by the name of the field |
| `ChartStyle` | [ChartDocument.jl:47](../../../source/domain/chart/ChartDocument.jl#L47) | colours, fonts, cycles, three numbers | by hand, `_or(style.x, theme.y)`; `grid_color` against `grid` |
| `SequenceChartStyle` | [SequenceChartDocument.jl:399](../../../source/domain/sequencechart/SequenceChartDocument.jl#L399) | colours, fonts, and pixel sizes that no scale applies to | by hand |

### I7. Graphics: the kinds of primitive and who handles each

Eleven drawn kinds (`GraphicsText`, `Rect`, `Line`, `Circle`, `Arc`, `Polyline`, `Polygon`, `Spline`, `Canvas`, `Viewport`, `Image`) and two marks (`Fence`, `PointerShape`).

| Job | Where | Form |
| --- | --- | --- |
| hit test of one element | `_hit_test_element` [GraphicsDocument.jl:1032](../../../source/platform/graphics/GraphicsDocument.jl#L1032) | `if … isa` chain, 10 kinds |
| bounds of one element | `extend_element_bounds!` [:1221](../../../source/platform/graphics/GraphicsDocument.jl#L1221) | `if … isa` chain, 11 kinds |
| paint | `SdlBackend.jl` (41 lines with `isa Graphics`), `WebBackend.jl` (24), `PdfWriter.jl` (13) (counts corrected by the check) | chains |
| walk of the elements of a canvas that meet a point or a clip (a list both ways from its head with an early stop, a vector from `compute_first_visible_index`) | `hit_element_at` [:953](../../../source/platform/graphics/GraphicsDocument.jl#L953); `_find_elements_shape!` [PointerShape.jl:39](../../../source/platform/graphics/PointerShape.jl#L39); `_render_canvas!` [SdlBackend.jl:2137](../../../source/backend/sdl/SdlBackend.jl#L2137); the dirty walk [SdlBackend.jl:3071](../../../source/backend/sdl/SdlBackend.jl#L3071); [WebBackend.jl:201](../../../source/backend/web/WebBackend.jl#L201) | written again in each |

Shared and sound: `TextMeasure` is an argument everywhere; `shift_event_position`, `shift_operation_position`, `read_child_move`, `read_child_leave` and `DrawnChild.jl` are written once.

### I8. The appearance against the settings

| Part | Appearance | Settings |
| --- | --- | --- |
| Declaration | `@theme struct` [Theme.jl:340](../../../source/platform/style/Theme.jl#L340): a docstring, a typed kind and a default for each field | `@settings struct` [SettingsGroup.jl:193](../../../source/platform/settings/SettingsGroup.jl#L193): a docstring, a type, a default and the allowed values |
| Container of one editor | `Appearance`, three `ThemeGroup` headings | `Settings`, a `CellVector` of groups |
| Root wrapper document | `AppearanceDocument(appearance, content)` | `SettingsDocument(settings, content)` |
| Wrapper projection | `AppearanceManagingProjection` [:23](../../../source/platform/appearance/AppearanceManagingProjection.jl#L23) | `SettingsManagingProjection` [:18](../../../source/platform/settingsmanaging/SettingsManagingProjection.jl#L18) |
| Rewrite of a plain write | `_wrap_theme_writes` [:111](../../../source/platform/appearance/AppearanceManagingProjection.jl#L111) | `wrap_setting_writes` [:99](../../../source/platform/settingsmanaging/SettingsManagingProjection.jl#L99) |
| Write with an effect | `ReplaceThemeValueOperation` [AppearanceOperations.jl:102](../../../source/platform/appearance/AppearanceOperations.jl#L102): print the view again | `ApplySettingOperation` [ApplySettingOperation.jl:111](../../../source/platform/settings/ApplySettingOperation.jl#L111): apply to the target |
| File | `appearance.toml`, `save_appearance!` / `load_appearance!` and 33 `_encode_` / `_decode_appearance_value` methods [Appearance.jl:352](../../../source/platform/style/Appearance.jl#L352) | `settings.toml`, `write_settings_file!` / `read_settings_file!` [SettingsFile.jl:29](../../../source/platform/settings/SettingsFile.jl#L29) |
| Save and Load buttons | `SaveAppearanceOperation`, `LoadAppearanceOperation` | `SaveSettingsOperation`, `LoadSettingsOperation` |
| Tab | `AppearanceToWidget.jl` (952 lines): a card for each theme, a row of name, control and docstring for each field | `SettingsToWidget.jl`, `SettingsGroupToWidget.jl` (394 lines): the same row |
| Control by the type of the value | `_make_field_control` methods [AppearanceToWidget.jl:422](../../../source/platform/appearance/AppearanceToWidget.jl#L422) | `_make_setting_control` [SettingsGroupToWidget.jl:136](../../../source/platform/settingsmanaging/SettingsGroupToWidget.jl#L136) |
| The generic control by type that exists | `make_object_field_widget` [ObjectFieldToWidget.jl:75](../../../source/platform/widget/ObjectFieldToWidget.jl#L75), used by neither tab | |

### I9. The plot slice and the chart domain (the overlap only)

`PlotModule` is pure arithmetic under the chart and the sequence chart. The sequence chart uses the axis scale, the ticks, the window and scroll bar functions and `get_series_color`. The decimation, the folds, the legend geometry and the values of bars and histograms have one user, the chart. The reviewer of the chart domain can judge whether they belong there.

## Findings

### LS-1 The appearance and the settings are one mechanism written twice

- **Kind:** several-ways · **Value:** high · **Effort:** large · **Confidence:** high
- **Principle:** 7 (one mechanism, a missing case gets its row), 8 (reuse an existing view), 3 (one way to edit).
- **Today:** Table I8 lists nine parts that exist twice. The two wrapper projections are the same code but for one call. Compare `read_intent` of [AppearanceManagingProjection.jl:51](../../../source/platform/appearance/AppearanceManagingProjection.jl#L51) with `read_intent` of [SettingsManagingProjection.jl:47](../../../source/platform/settingsmanaging/SettingsManagingProjection.jl#L47): the same IO map struct, the same `_CONTENT_STEPS`, the same three branches (collect, route, default), the same `_get_device_event` and `_get_collected_intents`, the same two reference maps. They differ in the function that rewrites the answer. Both tabs hold the same private helpers: `_place_caret` and `_find_last_range_step` are in [AppearanceToWidget.jl:926](../../../source/platform/appearance/AppearanceToWidget.jl#L926) and in [SettingsGroupToWidget.jl:272](../../../source/platform/settingsmanaging/SettingsGroupToWidget.jl#L272). Each tab chooses a control by the type of a value in its own table, and the generic table `make_object_field_widget` serves neither.
- **Example:**
  ```julia
  # today: a new kind of group that a person edits and saves needs all of these again
  @theme struct JsonTheme … end                       # or @settings struct RenderSettings … end
  AppearanceDocument(appearance, content)             # or SettingsDocument(settings, content)
  AppearanceManagingProjection(inner)                 # or SettingsManagingProjection(inner)
  ReplaceThemeValueOperation(write)                   # or ApplySettingOperation(write)
  save_appearance!(appearance, path)                  # or write_settings_file!(settings, path)

  # proposed: one group mechanism, two declarations on top of it
  @theme struct JsonTheme … end                       # adds the kinds and the scaled theme
  @settings struct RenderSettings … end               # adds the allowed values
  GroupManagingProjection(inner)                      # one wrapper for both documents
  ApplyGroupValueOperation(write)                     # effect by apply_group_change!(editor, group)
  write_group_file!(groups, path)                     # one codec by the type of the value
  ```
- **Problem:** A change of the wrapper pattern must be made twice, and the two copies already differ in small ways (the appearance copy handles `SystemColorsChange`, the settings copy does not need it). A value type that a theme can hold needs a control in one table and a codec in another, and a setting of that type needs both again. A third group of this kind would be a third copy.
- **Proposal:** One "described group" core: a document whose fields each have a docstring, a declared type and a default, with one table of field descriptions. `@theme` and `@settings` both build on it. One wrapper projection takes the rewrite as data. One wrapping operation writes and then calls an effect that the owner of the group type adds: print the view again for a theme, `apply_settings_to_editor!` for a settings group. One TOML codec keyed on the type of the value serves both files. One form projection draws the row of name, control and docstring, and takes the control from `make_object_field_widget`, which gets methods for `ThemeLength`, `ThemeColor`, `FontRole`, `StyleText` and `LineSpacing`.
- **What goes away:** one of the two managing projections (about 120 lines), one of the two rewrite functions, the appearance codec as a separate table (about 160 lines of `_encode_` / `_decode_`), the doubled tab helpers, and `_make_setting_control` and `_make_field_control` as private tables. Roughly 600 to 900 lines, and the need for a third copy.
- **What stays:** two tabs, as decision D8 of `plan/done/editor-settings.md` says; two files; the scales and the scaled theme; the allowed values and the environment variables of the settings; undo of a change through the window history.
- **Risk and open questions:** The appearance tab keeps its scroll place, its open cards and its caret inside the `Appearance`, because each change prints the whole view again (decision D9 of `plan/done/zoom-and-theme-controls.md`, style fields read with no edge). The shared form must keep that. I did not check whether the settings tab needs the same state.
- **Related plans:** `plan/done/editor-settings.md` (done; D8 two tabs, D14 undo; it asked for one shared file helper, which is only `get_configuration_folder` today), `plan/done/zoom-and-theme-controls.md` (done; D9, D13), `plan/done/settings-and-appearance-show-their-groups-in-the-explorer.md` (done).
- **Check:** confirmed-with-corrections. I read both wrapper projections line by line: the readers, the IO map, `_CONTENT_STEPS`, `_get_device_event`, `_get_collected_intents` and the two reference maps are the same text; `_place_caret` and `_find_last_range_step` are the same in both tabs; the 33 codec methods and the 41 `@theme` declarations count as stated; `make_object_field_widget` has no caller in either tab. Corrections: (1) Decision D16 of `plan/done/editor-settings.md` is not named. The owner rejected "sharing the private code of the appearance tab as a special mechanism" for the selection of the settings tab, which holds its selection "the normal way". So one form must use the way of the settings tab, and the appearance tab can follow only when a change no longer prints the whole view (D9). (2) The line count is too high. The 33 codec methods and the `_make_field_control` methods do not go away: they move and serve both, and the settings side has only two `_make_file_value` methods. A real saving is about 250 to 350 lines, not 600 to 900. (3) The reader of the wrapper (collect, route, default, over the field `content`) is also in `UndoBufferToAny.jl:110` and `FileToContent.jl:114`, so the shared part is a platform helper for a wrapper over a `content` field, not a `GroupManagingProjection`. (4) `ObjectToWidget` (`source/platform/widget/ObjectToWidget.jl`) is a third form of name and control, by reflection; the appearance plan left it because it shows no `StyleColor` and no `StyleFont` (`zoom-and-theme-controls.md` §3.8). This supports the one control table. The proposal loses no feature when the effect of a theme stays one `InvalidateProjectionOperation` for an answer, and the seams `apply_settings!` and `read_settings!`, the allowed values and the note "takes effect at the next start" stay. Value after the check: medium, because a domain already declares its theme in one line and no third kind of group is planned.

### LS-2 Five readers route an event to a placed child, each with another set of abilities

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** 7 (one mechanism for every list and every part), 6 (decide locally, delegate one level), `layout.md` "Every layout reader goes through one router".
- **Today:** Table I3. The layout document says that every layout reader goes through one router, but the slice has five. `_route_stack_event` handles `MouseClick`, `MouseScroll` and `MouseMove` by the point, and every other event falls to the selected child with its point not moved ([LayoutToGraphics.jl:2426](../../../source/platform/layout/LayoutToGraphics.jl#L2426)). So a `MouseDown`, a `MouseUp` and a `MouseDwell` in a `StackLayout`, a `ConstraintLayout` or an `AnchoredLayout` do not reach the child under the pointer, and no outward gesture is read there. The two list readers find the child at the point and give it the event, but give no leave to the child that the pointer was on and have no Tab walk. The scroll layout reader has no Tab walk.
- **Example:**
  ```julia
  # today: the same button, two answers
  VerticalLayout([WidgetButton("Run")])    # a MouseDown at the button sets `pressed`
  StackLayout([plot, WidgetButton("Run")]) # the MouseDown goes to the selected child, or to none

  # proposed: each layout gives the router three small functions and no reader of its own
  read_placed_children(document, evt;
      find_child_at = (x, y) -> …,   # the entry at a point: first, topmost, or a walk from the head
      find_selected = () -> …,       # the entry that the selection names
      steps_of      = k -> …)        # children[k], children[k][c], or the field of a part
  ```
- **Problem:** A new gesture or a new rule (the Alt+click of `read_child_event`, the leave of a move, a dwell) must be added in five places, and the table shows that it was added in some. A widget that works in a column fails in a stack or in a column of a list. The widget slice repeats the pattern again (34 events built by hand in `WidgetToGraphics.jl`).
- **Proposal:** One reader in the layout slice, `read_placed_children`, that holds the whole rule: Tab offered to the selected child and then the walk, the move with the leave, every pointer event moved with `shift_event_position`, the key to the selected child, and `read_container_gesture` at the end. A layout gives it how to find the entry at a point, the entry of the selection and the steps of an entry. The five readers become five calls.
- **What goes away:** `_route_stack_event`, `_route_to_children_reverse` and its three wrappers, `_route_click`, `_route_dwell`, `_route_scroll`, `_route_move`, `_route_downup`, `_translate_layout_list_event`, and the bodies of the list reader, the grid list reader and the scroll layout reader. About 200 lines, and the differences of table I3.
- **What stays:** the topmost child first for layouts whose children overlap; the walk from the head for a list; the field names of a scroll layout; `read_child_event` as the one place for the Alt+click rules.
- **Risk and open questions:** The Tab walk of a list needs `get_next_focusable_index` over a list with no count; it can walk the built children only. The same reader could serve the widget containers; that is the area of the widget reviewer.
- **Related plans:** `plan/pending/a-click-reaches-the-innermost-part-in-every-view.md` (in progress; it fixes clicks one view at a time and names the list layout and the anchored layout as places where a click is lost), `plan/pending/tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md` (deferred).
- **Check:** confirmed-with-corrections. I read the five readers. `_route_stack_event` gives only `MouseClick`, `MouseScroll` and `MouseMove` by the point and ends with no `read_container_gesture`; the two list readers give no leave and have no walk to a sibling for Tab; the scroll layout reader has no Tab walk. A live case exists: the one `StackLayout` of `source/` is the overlaid find bar (`FindBarViewToWidget.jl:51`), where a `MouseDown` on the content or on a button of the bar goes to the selected child. I found no document and no plan that gives a reason for the differences; the click plan in progress changes the backward maps only, and its branch changes no file of the layout slice. Corrections: the events built by hand count 6 in `LayoutToGraphics.jl`, 4 in `LayoutList.jl` and 34 in `WidgetToGraphics.jl` (corrected above). The Tab column belongs to the deferred Tab plan, so the one reader takes the Tab rule as it is today and decides nothing new. `plan/pending/feature-video-screenplays.md:101` records one more difference: a composite offers a drag event to each child when none is under the pointer, and a layout does not; the one reader must not lose that when it serves the widget containers. The proposal keeps the topmost child first, the walk from the head and the field steps of the scroll layout, and I found no feature that it loses. Value after the check: high.

### LS-3 The size protocol holds in three of the nine layouts

- **Kind:** partial-feature · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** `layout-rules.md` §1 ("One rule, both axes, no exceptions") and §7 ("there is no local limit"); principle 7.
- **Today:** Table I2. The row, the column and the grid give each child a range from its policy. `StackLayout` gives every child a free range on both axes and reads no weight, minimum or maximum of a `LayoutConstraint` ([LayoutToGraphics.jl:2458](../../../source/platform/layout/LayoutToGraphics.jl#L2458)), while `WidgetComposite`, the widget for overlapping children, gives each child the range of `make_cross_axis_context` on both axes ([WidgetToGraphics.jl:4319](../../../source/platform/widget/WidgetToGraphics.jl#L4319)). `FlowLayout` gives its children a free range ([:2205](../../../source/platform/layout/LayoutToGraphics.jl#L2205)). `ConstraintLayout` and `AnchoredLayout` take the size of their container from their own fields `bounding_width` and `bounding_height` and never from the range ([:2611](../../../source/platform/layout/LayoutToGraphics.jl#L2611), [:2810](../../../source/platform/layout/LayoutToGraphics.jl#L2810)).
- **Example:**
  ```julia
  # today
  VerticalLayout([LayoutConstraint(table; width = Fill)])   # the table is as wide as the column
  StackLayout([LayoutConstraint(table; width = Fill), badge]) # the table is as wide as its content
  ConstraintLayout(parts, relations; bounding_width = 800)  # the pane is 1200 wide; the layout does not know

  # proposed: no new call; the same lines follow the rule
  StackLayout([LayoutConstraint(table; width = Fill), badge]) # the table takes the edge of the stack
  ConstraintLayout(parts, relations)                         # anchor(0, :right) is the edge of the range
  ```
- **Problem:** `Fill`, `Fixed`, a minimum and a wrapped text do not combine with four layouts. A badge over a table needs a `WidgetComposite`, so a layout job goes to a widget. A constraint layout in a pane needs a number that somebody typed.
- **Proposal:** One function makes the offer of a child from a policy and a range, for an axis that the layout divides (`_main_context`) and for an axis that it does not (`make_cross_axis_context`). Every layout calls it. A layout whose children overlap (stack, constraint, anchored) uses the second form on both axes, as `WidgetComposite` does now. `bounding_width` and `bounding_height` stay as an authored size, and 0 means the range that the parent gives. A flow gives each child a bounded width, the break width.
- **What goes away:** the free-range lines of the stack and the flow; the special reading of the constraint wrapper for "a parent that gives no exact size, such as a stack or a flow" ([:633](../../../source/platform/layout/LayoutToGraphics.jl#L633)); the reason to use `WidgetComposite` for a plain overlay.
- **What stays:** every layout kind and every field; an authored bounding size; the two-pass print of the constraint layout.
- **Risk and open questions:** Examples and omnet-julia views that rely on a free range in a stack would change their size. The guard of `test_layout_rules()` "fails for a type with no kind". Corrected by the check: the guard already gives `FlowLayout` and `StackLayout` the kind `:places`, and it exempts `AnchoredLayout` and `ConstraintLayout` with a stated reason (`test/platform/projection/LayoutRulesTest.jl:114`), so a change of what these layouts offer changes those rows.
- **Related plans:** `plan/tentative/layout-extensions.md` (stale; its §3 wants the widget containers folded onto the layouts, which needs this first).
- **Check:** weakened. The facts of the stack hold: `StackLayout` gives each child a free range on both axes (`:2459`), and the function that the proposal asks for exists already: `make_cross_axis_context` (`:1298`) serves the cross axis of a row and a column and both axes of `WidgetComposite`. The one `StackLayout` of `source/`, the overlaid find bar (`FindBarViewToWidget.jl:51`), gives its content a free range, so the gap is live. But the title is too strong, and three of the four differences have a stated reason. `LayoutConstraint` forwards the range and `ScrollLayout` gives its center the range less the bands, so five of the nine follow. `test_layout_rules()` gives `FlowLayout` and `StackLayout` a kind (`:places`) and exempts `AnchoredLayout` ("an anchored layout places its entries by the points of its content") and `ConstraintLayout` ("a constraint layout sizes its children by its solver") with a reason (`LayoutRulesTest.jl:114`). The flow states its reason at `:2194`, and `layout.md` states that an annotation never moves its content. `ConstraintLayout` and `AnchoredLayout` have no use in `source/` outside the slice (one `AnchoredLayout` in omnet-julia). The proposal would lose one case: with "0 means the range that the parent gives", a constraint layout or an anchored layout in a bounded range takes the edge, where today it takes the extent of its children or of its content; the rule must read an exact range only. What holds: the stack calls `make_cross_axis_context` on both axes, and a flow gives its children the break width as a bounded width. Value after the check: medium.

### LS-4 Each layout has a second printer for a lazy list, and the grid a third

- **Kind:** several-ways · **Value:** high · **Effort:** large · **Confidence:** medium
- **Principle:** the settled decision "one generic solution for every list; a lazy list counts from its head"; principle 7.
- **Today:** `print_document` of a row, a column and a grid branches on the type of `children` ([LayoutToGraphics.jl:1196](../../../source/platform/layout/LayoutToGraphics.jl#L1196), [:1503](../../../source/platform/layout/LayoutToGraphics.jl#L1503), [:1765](../../../source/platform/layout/LayoutToGraphics.jl#L1765)) into `LayoutList.jl` (375 lines), `GridList.jl` (477) and `GridColumnList.jl` (283). Each has its own IO map type, its own state, its own reference maps and its own reader. Table I4 shows what the list forms lack. The flow, the stack, the constraint layout and the anchored layout take no list at all. The same branch `isa ListNode` stands in 26 files, down to the three backends.
- **Example:**
  ```julia
  # today: the print of a column is one of two functions with two IO maps
  doc.children isa ListNode && return _print_layout_list(p, recursion, doc, ctx, :y)   # LayoutListIoMap
  build = Cell(@computation _vl_build(recursion, doc, ctx))                            # ChildrenIoMap

  # proposed: one printer over one walk; the count is an ability of the walk, not a type
  places = make_child_places(doc.children, …)   # from the head, each after its neighbour
  has_known_count(doc.children) && share_weights!(places, …)
  ```
- **Problem:** A feature of a layout is added to one printer and is missing in the other: the ring, the backward map, the baseline, the span. A view that moves from a vector to a list for size loses them with no error. The next layout feature has to be written two or three times.
- **Proposal:** One printer for each layout over a walk of the children that starts at an anchor and has an optional count. A vector is a walk with a count and with index access. Abilities that need a count (a weight on the main axis, a `Content` column) depend on `has_known_count`, and every other ability (ring, maps, Tab, leave, alignment, span) is written once. LS-2 gives the one reader. The IO map is one type with a function that finds the entry of an index.
- **What goes away:** `LayoutListIoMap`, `GridLayoutListIoMap`, the second set of reference maps and readers, and in the end most of the 1 135 lines of the three list files or most of `_hl_build` and `_vl_build`.
- **What stays:** lazy build of only the children that show; the kept prints of a list (`KeptListPrints`); `PlaceBlocks` for a vector, where a total over all children is cheap; the errors for a weight on a list.
- **Risk and open questions:** A vector places a child from block totals in log steps, and a list places a child after its neighbour. One printer must keep both costs. The owner has not decided the generic memory solution for lists, and this proposal must follow it. The same merge would reach the table, the tree and the backends; those are other areas (widget, collection, backend).
- **Related plans:** `plan/pending/a-click-reaches-the-innermost-part-in-every-view.md` (in progress; covers the missing backward map of the list forms only), `plan/pending/guards-keep-the-frame-short-at-any-size.md` (pending; measures the list forms, changes no structure), `plan/done/a-layout-paints-only-what-the-screen-shows.md` (done; D9, added by the check).
- **Check:** weakened. The facts hold: three list files (375, 477 and 283 lines) with their own IO maps and readers, and the list forms have no ring, no backward map, no baseline, no span, no leave and no Tab walk. But the two forms have a stated and approved reason. D9 of `plan/done/a-layout-paints-only-what-the-screen-shows.md` rejected "a layout of a vector that prints only the children on the screen": "Its extent needs the extents of the children that it does not print. A layout of a list solves this, because it has no extent on its main axis." So "one printer" is two code paths under one name. Which children are built, how a place is computed (`PlaceBlocks`, or after the neighbour), the form of `elements` (`CellVector` or `ListNode`), the form of a reference (an index, or a count from the head) and the extent all differ, and the claim that most of the 1 135 lines or most of `_hl_build` and `_vl_build` go away has no support. The backward map is step 5 of the click plan in progress, and `layout.md` lists the limits of the list forms. The proposal also depends on the generic memory solution for lists, which the owner has not decided, so a merge of the printers now would be made before that decision. What holds is table I4: each ability is written once over an entry `(x, y, child IO map)` and both forms call it (the ring, the baseline offset, the span), and LS-2 gives the one reader. Value after the check: medium, for the abilities and not for the merge of the printers.

### LS-5 The axis is not a value, so each rule of a stack is written once for the width and once for the height

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** `layout-rules.md` §7 ("there is no per-axis rule: width and height differ only in the range that a parent gives").
- **Today:** `_hl_build` ([LayoutToGraphics.jl:1077](../../../source/platform/layout/LayoutToGraphics.jl#L1077), 114 lines) and `_vl_build` ([:1378](../../../source/platform/layout/LayoutToGraphics.jl#L1378), 120 lines) are mirror copies, and each comment calls the other "the mirror". The grid writes the edge of a `Content` column and of a `Content` row as two closures ([:1872](../../../source/platform/layout/LayoutToGraphics.jl#L1872), [:1891](../../../source/platform/layout/LayoutToGraphics.jl#L1891)), and the policies, the offers and the shares as pairs. `HorizontalLayout` and `VerticalLayout` are two document types with the same five fields but for `vertical_align` and `horizontal_align`. The list form already takes the axis as an argument and serves both types with one function ([LayoutList.jl:121](../../../source/platform/layout/LayoutList.jl#L121)), with 22 `axis === :y ? … : …` choices. The cause is in `PrinterContext`: four fields `minimum_width`, `maximum_width`, `minimum_height`, `maximum_height` and keyword pairs `width =`, `height =`.
- **Example:**
  ```julia
  # today
  floor_w = ctx.maximum_width === nothing ? ctx.minimum_width : nothing     # _hl_build
  floor_h = ctx.maximum_height === nothing ? ctx.minimum_height : nothing   # _vl_build
  axis === :x ? with_exact_size(ctx; width = cell) : with_exact_size(ctx; height = cell)

  # proposed
  range = get_range(ctx, main)                 # (minimum, maximum) of one axis
  floor = range.maximum === nothing ? range.minimum : nothing
  with_exact_size(ctx, main, cell)             # the axis is an argument
  ```
- **Problem:** The baseline alignment exists in the row and has no twin in the column, by design, but every other change (the shared minimum, the space of a slot, the room of an unweighted child) had to be made in both builds and in both halves of the grid. Three helpers of an older allocation are left with no caller (`_alloc_cell` [:571](../../../source/platform/layout/LayoutToGraphics.jl#L571), `_hl_alloc_child_x_cell`, `_vl_alloc_child_y_cell`).
- **Proposal:** An axis value (`:x`, `:y` or a small type) with `get_range(ctx, axis)`, `get_extent(iomap, axis)`, `get_space(ctx, axis)` and size helpers that take the axis. One `_build_stack(recursion, doc, ctx, main)` serves the row and the column; the baseline is the cross alignment of a row. One function shares one axis of a grid and is called for the columns and for the rows.
- **What goes away:** one of `_hl_build` and `_vl_build`, half of the paired closures of the grid, the three dead helpers; about 250 lines in the layout slice. The 30 `axis === …` choices of `WidgetToGraphics.jl` can follow.
- **What stays:** both document types and their field names, which are the reference vocabulary of saved files.
- **Risk and open questions:** `PrinterContext` is in the kernel; its file is not sealed (`SEALING.md:243`, corrected by the check). The helpers with an axis argument can be added in the layout slice over the four fields, so the kernel need not change first.
- **Related plans:** none found.
- **Check:** confirmed-with-corrections. A diff of `_hl_build` and `_vl_build` with the axis words made equal leaves only the baseline lines. The three helpers have no caller in `source/`, `test/` and `example/`. No plan covers it, and no document gives a reason for two builds. Corrections: the title is too strong. The axis is already a `Symbol` argument of `_main_context`, `make_cross_axis_context`, `layout_weight`, `layout_min`, `layout_max`, `layout_preferred`, `with_free_axis` and `_get_child_space`, and `allocate_axis` works on the numbers of one axis, so the missing part is small: `get_range(ctx, axis)`, the size helpers with an axis, and one build. `WidgetToGraphics.jl` has 30 `axis === …` choices, not 34 (corrected above). The proposal loses no feature; the baseline stays the cross alignment of a row. Value after the check: medium.

### LS-6 Each consumer of a canvas repeats the walk of its elements and the case over the kinds of primitive

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** architecture decision 4 (multiple dispatch, "no explicit type-case"); principle 7 (a missing case gets its row in the generic mechanism).
- **Today:** Table I7. The walk "the elements of a canvas that meet a point or a clip" is written in `hit_element_at` ([GraphicsDocument.jl:953](../../../source/platform/graphics/GraphicsDocument.jl#L953), 78 lines with three copies of the early stop), in `_find_elements_shape!` ([PointerShape.jl:39](../../../source/platform/graphics/PointerShape.jl#L39)), in the SDL render and in the SDL dirty walk ([SdlBackend.jl:2137](../../../source/backend/sdl/SdlBackend.jl#L2137), [:3071](../../../source/backend/sdl/SdlBackend.jl#L3071)) and in the web backend. `graphics.md` says that the dirty walk and `hit_element_at` "follow the same rule". The kinds of primitive are handled by `if … isa` chains: 10 kinds in `_hit_test_element`, 11 in `extend_element_bounds!`, and 41, 24 and 13 lines with such a test in the three backends. The hit test of five kinds is a test of the same box that `extend_element_bounds!` computes with its own code.
- **Example:**
  ```julia
  # today: a new primitive (GraphicsArc was the last) needs a branch in each chain
  elseif elem isa GraphicsArc
      _is_point_on_arc(elem, x, y)            # GraphicsDocument.jl:1047, and again for the bounds,
                                              # and in SdlBackend, WebBackend, PdfWriter

  # proposed: one method per job, next to the type
  get_element_box(arc::GraphicsArc, measure) = …
  is_point_on_element(arc::GraphicsArc, x, y) = _is_point_on_arc(arc, x, y)
  draw_element(backend::SdlBackend, arc::GraphicsArc, frame) = …   # in the backend
  for element in each_element_at(canvas, x, y) … end              # the one walk
  ```
- **Problem:** A chain gives no error for a kind that it does not know: the bounds are empty and the hit test is false. A new kind, a new kind of collection, or a third layout direction needs an edit in each copy of the walk. The planned Cairo backend would add one more copy of both.
- **Proposal:** In the graphics slice: an iterator for the walk (`each_element_between(canvas, near, far)` and `each_element_at(canvas, x, y)`), and two generic functions with a method for each kind, `get_element_box` and `is_point_on_element`, whose default is the box test. `hit_element_at`, the bounds, the pointer shape, `find_reference_box` and the backends use them. Each backend adds methods of one `draw_element`.
- **What goes away:** the three copies of the early stop in `hit_element_at`, the walk of `_find_elements_shape!`, the two chains of the graphics slice, and the walk in each backend; about 250 lines in the graphics slice and more in the backends.
- **What stays:** every kind of primitive, the fence, the declared extent, the rule that a producer declares no overlap, and the cost of the SDL paint (the iterator must read the same cells in the same order, because a read of an element is a dependency).
- **Risk and open questions:** The SDL dirty walk tests the validity of a cell before it reads it; the shared walk must let a caller do that. This reaches the area of the backend reviewer.
- **Related plans:** `plan/pending/cairo-glfw-backend.md` (not started, stale paths; it plans to port the painter set of the PDF backend).
- **Check:** confirmed-with-corrections. I read `hit_element_at`, `_hit_test_element`, `extend_element_bounds!`, `_find_elements_shape!`, `_render_canvas!` and `_dispatch_render_elem!`. The chains and the walks are as stated, and no document gives a reason for a chain. Corrections: the lines with `isa Graphics` count 41 in `SdlBackend.jl`, 24 in `WebBackend.jl` and 13 in `PdfWriter.jl` (corrected above). `SdlBackend.jl` walks the list of a canvas in six places (`:2146`, `:2667`, `:3400`, `:3630`, `:3921`, `:4105`), not two, and the web backend reads every node of a list with no edge (`_list_nodes`, `WebBackend.jl:199`), so the walk has more copies than the finding says, and one of them does not keep the rule of `graphics.md`. `cairo-glfw-backend.md` itself says that the render walk "already exists twice" and plans a port. Architecture decision 4 speaks of projections, so it supports the methods by kind only by analogy. Two limits for the proposal: the docstring of `extend_element_bounds!` promises that "a type this slice does not know" adds nothing, so the default methods must keep that. And the SDL walks differ in what they do at a node (a guarded read of the start, the key of a partial paint, a node that waits for the start of the next one, the validity test of the dirty walk), so the iterator must take the read of the start from its caller and give the node; else it serves only the hit test and the pointer shape. The methods by kind are the safe part. Value after the check: medium.

### LS-7 A colour and a font come from a shared role, a length does not

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** `spacing-rules.md` R4 ("One value for one relation … the distance comes from one scale of roles"); the decision of `plan/done/the-window-has-one-table-of-font-roles.md` for fonts.
- **Today:** A colour field names a role of `ColorTheme` and a font field names a role of `FontTheme`, both in the style slice ([ThemeColor.jl:60](../../../source/platform/style/ThemeColor.jl#L60), [FontRole.jl:51](../../../source/platform/style/FontRole.jl#L51)). A length field holds a number. The roles of spacing, radius and line width are fields of `WidgetTheme` in the widget slice ([WidgetTheme.jl:116](../../../source/platform/widget/WidgetTheme.jl#L116)), so a theme below or beside the widgets restates the number: `radius = Radius(6)` in `WidgetTheme` and `node_radius = Radius(6)` in [GraphTheme.jl:28](../../../source/domain/graph/GraphTheme.jl#L28); `container_padding = Spacing(8)` and `node_padding = Spacing(8)`, `padding = Spacing(8)` in [ChartTheme.jl:67](../../../source/domain/chart/ChartTheme.jl#L67), `collection_gap = Spacing(8)` in [GraphicsTheme.jl:27](../../../source/platform/graphics/GraphicsTheme.jl#L27). Counts are in I5: 13 radius literals, 16 line width literals and 55 spacing literals in 16 theme files.
- **Example:**
  ```julia
  # today
  node_radius::Radius   = Radius(6)          # GraphTheme: the same 6 as WidgetTheme.radius, by hand
  node_fill::ThemeColor = ColorRole(:surface)

  # proposed
  node_radius::ThemeRadius = RadiusRole(:control)      # follows the one role
  node_padding::ThemeSpacing = SpacingRole(:container_padding)
  ```
- **Problem:** A person who makes the corners rounder in the appearance tab changes the widgets and not the nodes of a graph, the legend of a chart or the selection ring. The scales move all of them together, but the roles do not. The builder of a domain that wants the widget roles must take a second theme, `widget_theme`.
- **Proposal:** A third shared theme in the style slice beside `ColorTheme` and `FontTheme`, with the roles of section 3 of `spacing-rules.md` and the radius and line roles. `SpacingRole`, `RadiusRole` and `LineRole` name a role, as `ColorRole` and `FontRole` do, and a field can still hold an exact length. `WidgetTheme` names the roles.
- **What goes away:** the restated numbers in the themes whose job is a role; the `widget_theme` argument of builders that take it only for a gap.
- **What stays:** an exact length where the job is no role (the tick spacing of a chart); the five scales; the values that the owner chose (`Inset(4, 4, 8, 8)` and 8).
- **Risk and open questions:** Which lengths of the chart, the graph and the sequence chart are roles and which are their own is a design choice for the owner. Decision D14 of `plan/done/zoom-and-theme-controls.md` rejected a ramp of sizes; named roles are not a ramp.
- **Related plans:** `plan/done/spacing-starts-from-first-principles.md` (done), `plan/done/the-window-has-one-table-of-font-roles.md` (done), `plan/pending/line-spacing-from-the-theme.md` (pending, moved into another plan).
- **Check:** weakened. The counts hold after a small correction: 13 radius, 16 line width and 55 scalar spacing literals, `Spacing(8)` 15 times, in 16 theme files. But a length has a role model today, and it was decided. `spacing-rules.md` §3 says: "A role is a field of `WidgetTheme`", "A theme of a slice holds a space only where the job is not a role above" and "The builder of a slice takes a `widget_theme` and reads the roles above". D14 of `plan/done/zoom-and-theme-controls.md` chose "named values, one for each use", and D17 a theme for each domain that draws. So `node_radius`, `node_padding` and the padding of a chart are named values of their own use by that decision, and the `widget_theme` argument (38 lines in 9 files of `source/domain`) is the documented way, not a way around a gap. Of the 18 literals `Spacing(8)` and `Radius(6)`, 6 are in `WidgetTheme` and 12 in nine other themes. What remains true: a theme below the widget slice (`GraphicsTheme.collection_gap`) can not name a role, and a length field can not point at a role as `ColorRole` and `FontRole` do. That is a question for the owner about the place of the roles, not a fault of the code, and the proposal changes a rule that `spacing-rules.md` states. Value after the check: low.

### LS-8 A style of one document over its theme has three unrelated shapes

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** 7 (one mechanism); principle 1 for the sizes that no scale reaches.
- **Today:** Table I6. `WidgetStyle.jl` declares 24 document types; each repeats the five fields `margin_color`, `border_color`, `padding_color`, `content_color`, `label_text_color`, every field is `::Any`, and a field must have the name of a style field of the projection ([WidgetStyle.jl:25](../../../source/platform/widget/WidgetStyle.jl#L25), [WidgetToGraphics.jl:58](../../../source/platform/widget/WidgetToGraphics.jl#L58)). In `source/`, `WidgetStyle` is made in 15 places and the 23 other types in one place together (`WidgetCardStyle` in `OutlineRow.jl`). A widget style overrides a colour only. `ChartStyle` and `SequenceChartStyle` merge by hand with `_or(style.x, theme.y)` ([ChartPlotToGraphics.jl:29](../../../source/domain/chart/ChartPlotToGraphics.jl#L29)). `SequenceChartStyle` holds pixel sizes (`event_radius = 3`, `arrowhead_size = 8`) that the printer uses as they are, so the scales of the appearance do not reach them ([SequenceChartDocument.jl:407](../../../source/domain/sequencechart/SequenceChartDocument.jl#L407), [SequenceChartPlotToGraphics.jl:670](../../../source/domain/sequencechart/SequenceChartPlotToGraphics.jl#L670)).
- **Example:**
  ```julia
  # today
  WidgetCard(…; style = WidgetCardStyle(; plain_border_color = line))   # a type for each widget type
  Chart(…; style = ChartStyle(grid_color = color))                      # grid_color here, grid in the theme

  # proposed: one override type; the names and the kinds are those of the style fields
  WidgetCard(…; style = StyleOverride(plain_border_color = line, title_text = FontRole(:section)))
  Chart(…; style = StyleOverride(grid = color))
  ```
- **Problem:** A new widget part needs a field in the projection, a derivation in the builder and a field in a style type of its own. A style cannot change a font, a radius or a padding of one widget. A typo in a field name of a hand-made style type is found only where `hasfield` returns false.
- **Proposal:** One override document that holds values by the name of a style field, checked against the style fields of the projection that reads it, for any kind of value. One function merges it over the styles (`get_part_style(p, w, name)`), and a length in it has a kind, so a scale applies. The chart and the sequence chart keep their non-visual knobs (`marker_limit`, `split_horizon_viewports`) in a settings part of the document and take their visual overrides the same way.
- **What goes away:** 23 style types (about 440 lines), `_get_part_color`, `_get_part_text`, `_get_part_stroke` as three functions, the `_or` merges of the two charts.
- **What stays:** `WidgetStyle(; content_color = …)` as it is written today in 15 places; the rule that a disabled field ignores the override; shared style documents.
- **Risk and open questions:** Saved `.pred` files that name one of the 23 types need a reader for the old names, or the types stay as constructors. The chart part reaches the area of the chart reviewer.
- **Related plans:** `plan/done/a-projection-holds-its-styles.md` (done; the owner decided that a projection holds its styles as fields, which this keeps), `plan/done/widget-color-design.md` (done; D2 and D12, added by the check).
- **Check:** weakened. The facts hold: 24 style types, five repeated fields, `::Any`, the match by `hasfield`; `WidgetStyle` is made in 15 places of `source/`, `WidgetCardStyle` in one and the 22 other types in none (`test/platform/projection/WidgetColorTest.jl` makes two more of them); the two charts hold 29 `_or` merges; `event_radius` and `arrowhead_size` are used as they are. But the shapes are not unrelated. D2 of `plan/done/widget-color-design.md` (owner, 2026-09-22) chose one field `style` that holds a `WidgetStyle` document "in the form of `ChartStyle`", with the reasons that a person edits a style "like any other document" and that many widgets share one. D12 keeps an inset apart from its colour. That plan is about colours, and `text_style` of a label and the inset fields of a widget are the stated ways for a font and a padding. The proposal loses what a typed style gives: a wrong keyword fails when the style is made (the Problem above says the opposite; an override by name can be checked only at a print), a docstring for each field, the form of the document in the editor, and the fields that reflection gives the assistant. What holds is smaller. The style type for each widget type comes from a decision of the implementation (§8.2 of that plan), not from the owner, and 22 of them have no use in `source/`. The two charts merge by hand, under other names than their theme. The pixel sizes of `SequenceChartStyle` pass no scale. A proposal that keeps D2: one merge function by the name of the field for every style document, the chart fields named as the theme fields, and a kind for each size. Value after the check: low in this area; the chart part is for the reviewer of the chart domain.

### LS-9 Two colours and one constant enter beside the chain

- **Kind:** special-case · **Value:** low · **Effort:** small · **Confidence:** high
- **Principle:** `style.md`, "One colour type from the domain to the backend"; "A projection holds its styles, and its builder fills them".
- **Today:** `WindowDocument.bg` is four bytes with the constant `DEFAULT_BG = (249, 249, 251, 255)` ([ScreenDocument.jl:35](../../../source/platform/screen/ScreenDocument.jl#L35), [:93](../../../source/platform/screen/ScreenDocument.jl#L93)); `PdfWriter.jl:4` holds the same constant again. The appearance reaches it by a search of the screen through up to 16 wrappers and a `set_cell_computation!` on the field from outside ([AppearanceWrapper.jl:62](../../../source/platform/appearance/AppearanceWrapper.jl#L62)), and a window opened later shares the cell of the first window ([WindowManaging.jl:282](../../../source/platform/screen/WindowManaging.jl#L282)). `default_color_cycle()` computes eight colours from the default palette in the light mode ([PlotStyle.jl:27](../../../source/platform/plot/PlotStyle.jl#L27)); the charts take `series_colors` of their theme, and the function is left as the fallback of an empty cycle.
- **Example:**
  ```julia
  # today
  set_cell_computation!(getfield(window, :bg), () -> _get_background_bytes(appearance))

  # proposed: the screen projection holds the style, as every projection does
  ScreenToScreen(inner; background = get_widget_style(theme, :background))   # a StyleColor
  ```
- **Problem:** The background is the one colour that is not a `StyleColor` and not a style field of the projection that prints it. It follows the appearance only through a start step that finds the screen from outside ([AppearanceWrapper.jl:30](../../../source/platform/appearance/AppearanceWrapper.jl#L30)), and a screen with no first window gives the constant. A second source of the colours of series exists with a fixed mode.
- **Proposal:** The background is a `StyleColor` style of `ScreenToScreen`, filled by its builder from the role `background`; a backend converts it as it converts every colour. `get_series_color` takes its fallback from the cycle that the caller gives, and `default_color_cycle` goes.
- **What goes away:** `follow_window_backgrounds!`, `_find_screen_document`, `_get_background_bytes`, `_get_screen_background`, both `DEFAULT_BG` constants, `default_color_cycle`.
- **What stays:** a window of its own background (`OpenWindowOperation(bg = …)`), as a `StyleColor`.
- **Risk and open questions:** Whether a saved window file holds `bg`; if so the reader needs the old form.
- **Related plans:** `plan/done/one-coherent-color-set.md` (done; its notes M5 and M6 record both points as open follow-ups; added by the check).
- **Check:** confirmed. `DEFAULT_BG` stands in `ScreenDocument.jl:35` and in `PdfWriter.jl:4`. `follow_window_backgrounds!` searches up to 16 wrappers and sets the computation of `bg` from outside. A later window shares the cell of the first window. `default_color_cycle` has one caller, the fallback at `PlotStyle.jl:54`. `plan/done/one-coherent-color-set.md` gives the reason of the bytes: "The kernel can not name a `StyleColor`". The window document is in the platform, and the screen slice already uses the graphics slice, so that reason does not bind it. The proposal keeps the background of one window. One case to keep: an editor with `appearance = false` and an image export still get the light background of the default palette, from the default theme. Value after the check: low.

### LS-10 The screen slice restates three things that exist elsewhere

- **Kind:** complicated-api · **Value:** low · **Effort:** small · **Confidence:** medium
- **Principle:** 3 (one way to edit), PAR-REGISTER-NEW-OPERATION (one place where a path-carrying operation is registered), principle 7.
- **Today:** (a) `OpenWindowOperation` has 15 fields, 14 of them the fields of `WindowDocument` ([ScreenDocument.jl:174](../../../source/platform/screen/ScreenDocument.jl#L174), [:84](../../../source/platform/screen/ScreenDocument.jl#L84)); `_make_opened_window` and `_update_window!` copy them one by one ([WindowManaging.jl:268](../../../source/platform/screen/WindowManaging.jl#L268), [:289](../../../source/platform/screen/WindowManaging.jl#L289)). `screen.md` says "To open a window, a program adds a `WindowDocument` to `windows`". (b) `_prefix_op` re-roots an operation with its own case over six operation types before it falls back to the kernel's `reroot_operation` ([ScreenToScreen.jl:498](../../../source/platform/screen/ScreenToScreen.jl#L498)); its comment says "Every path-carrying operation type must be handled here". (c) A box beside an anchor is placed by two algorithms: `_anchored_place` tries four sides and clamps into a region ([LayoutDocument.jl:970](../../../source/platform/layout/LayoutDocument.jl#L970)), and `compute_anchored_place` knows `:below` and `:center`, flips above and slides into a display area ([WindowPlacement.jl:117](../../../source/platform/screen/WindowPlacement.jl#L117)).
- **Example:**
  ```julia
  # today
  OpenWindowOperation(; id, title, x, y, width, height, minimum_size, maximum_size, bg, style,
                        auto_dismiss, modal, placement, content, selection)
  # proposed
  OpenWindowOperation(WindowDocument(; id, title, style = :floating, content); selection)
  ```
- **Problem:** A new field of a window needs four edits. A new operation type with a path must be known to the screen as well as to the kernel. A tooltip can not stand left of its part, and an annotation can not slide.
- **Proposal:** `OpenWindowOperation` holds a `WindowDocument` and the selection. `_prefix_op` calls `reroot_operation` for every operation; a type that needs another rule gets a method there. One pure function places a box beside an anchor in a region, with the side, the gap, the flip and the slide, and both callers use it.
- **What goes away:** 13 fields and two copy functions; the case of `_prefix_op` (and its likes in `VersioningToAny.jl:247` and `WidgetToGraphics.jl:1901`, which are other areas); one of the two placement functions.
- **What stays:** the keyword form of the operation as a constructor; the popup that follows its window; the stacking of anchored children.
- **Risk and open questions:** I did not check whether `reroot_operation` gives the same result as each branch of `_prefix_op` (the branch for `ReplaceReferencedValueOperation` keeps an operation that carries its own root).
- **Related plans:** `plan/pending/a-tooltip-opens-beside-the-pointer-at-any-density.md` (steps 1 to 3 done, on main; a fault of the place of a tooltip window, no change of the two algorithms).
- **Check:** confirmed-with-corrections. (b) I closed the open question: each branch of `_prefix_op` gives what `reroot_operation` gives. The two range operations register `operation_reference` and `retarget_operation` (`PrimitiveDocument.jl:299`); a `ReplaceReferencedValueOperation` that carries its own root comes back unchanged from both (`Rerooting.jl:56`, `:62`); the path, compound, wrapping and collected cases each have a kernel method (`Rerooting.jl:37`, `:39`, `:44`, `Intent.jl:158`). So `_prefix_op` of the screen and of `VersioningToAny.jl:240` can go with no change of a result. (a) holds, with a limit: the operation is not a plain copy of the document. Its defaults differ (`width = 0`, `title = ""`); `bg = nothing` means "follow the screen" at an open and "keep" at an update; an operation for an id that exists updates the window and keeps its identity; and `_place_dialog_at_main_window` writes `x` and `y` of the operation again. An operation that holds a `WindowDocument` must keep these four, so `bg` of the document must take `nothing`, and the update still copies fields. (c) holds, but the two algorithms serve other models: a region from the origin, with an axis that can have no bound and children that stack, against the areas of several displays. One function is a small gain there. Value after the check: low; (b) is the part to do.

## Covered by plans

- `plan/tentative/layout-extensions.md` (stale, old paths): the widget containers and the table place their parts with their own arithmetic instead of the layouts. `layout.md` lists it under Limits.
- `plan/pending/a-click-reaches-the-innermost-part-in-every-view.md` (in progress, step 5): the backward map of a layout of a list and of the anchored layout.
- `plan/pending/tab-and-the-arrows-reach-every-part-that-takes-the-keyboard.md` (deferred): the model of the Tab and arrow walk between siblings.
- `plan/pending/line-spacing-from-the-theme.md` (pending): the line spacing as a theme value.
- `plan/pending/cairo-glfw-backend.md` (not started): a fourth backend; see LS-6.
- `plan/pending/chase-animation.md` (not started): the animation of a switch as a projection; no overlap with a finding.
- `plan/pending/guards-keep-the-frame-short-at-any-size.md` (pending): frame time guards for the list layouts; no structure change.

## Examined and sound

- `allocate_axis` is the one allocator for the stacks, the grid and the split pane ([LayoutDocument.jl:745](../../../source/platform/layout/LayoutDocument.jl#L745)).
- A size policy belongs to the placement (`LayoutConstraint`, `child_width`), not to the widget: the same card fills a column and is content-wide in a toolbar.
- `PlaceBlocks` gives a column, a row and the lines of a text one structure for totals in log steps.
- The constraint solver is behind a seam and the dependency is in the adapter `ProjecturedTulip`, as the owner decided for new dependencies.
- All 41 themes use `@theme`, and the theme files of the domains follow one pattern: a role for each colour and each font, a docstring for each field.
- A projection holds its styles as fields and its builder fills them, one field for each value or one `NamedTuple` of all values. The owner decided this in `plan/done/a-projection-holds-its-styles.md`; both forms fit it.
- Style fields read the theme with no edge, and a change prints the whole view again. This is decision D9 of `plan/done/zoom-and-theme-controls.md`, with its known limit that a write that passes no reader does not print the view again. I name it only because the state of the appearance tab inside the `Appearance` follows from it.
- The three tiers of a colour (palette ramp, role of `ColorTheme`, field of a theme) are a usual token model; the palette names of `WidgetTheme` are the component tier, not a duplicate.
- Literal colours, fonts and gaps outside the themes are almost none; the style guard and the gap guard work.
- The palette registry `_PALETTES` and the cache `_THEME_DEFAULTS` are global, but they hold read-only data that is the same for every editor, which PAR-PER-EDITOR-STATE allows.
- `TextMeasure` is an argument of every function that measures, so the graphics slice calls no font backend.
- The plot slice is pure arithmetic below two domains, and it defines no document type.
- `shift_event_position`, `shift_operation_position`, `read_child_move`, `read_child_leave` and `DrawnChild.jl` are written once for all containers; LS-2 asks only that the layout readers use them everywhere.
- The primitive slice: one string range edit serves every field kind through `splice_value!`; the number edit is separate for a stated reason.

## Check of the report

A second reviewer tried to refute each finding at commit 3a9b4fae4: every cited file was opened, each count was made again with grep, and the plans and the rule documents were searched for a reason of each difference. The corrections stand in the text above, and each finding has a **Check** item.

| Id | Verdict | Value after the check | The main point of the check |
| --- | --- | --- | --- |
| LS-1 | confirmed-with-corrections | medium | The copies are real. D16 of `editor-settings.md` keeps the two selection models apart; the saving is about 300 lines, not 600 to 900; the wrapper over `content` has four copies, not two. |
| LS-2 | confirmed-with-corrections | high | The five readers differ as table I3 says, with a live case in the overlaid find bar. The Tab column belongs to a deferred plan. |
| LS-3 | weakened | medium | Five of nine layouts follow. The rule test gives the flow and the stack a kind and exempts the anchored and the constraint layout with a reason. `make_cross_axis_context` exists; the stack does not call it. |
| LS-4 | weakened | medium | The two printers have an approved reason (D9 of `a-layout-paints-only-what-the-screen-shows.md`). The missing abilities of the list forms are real and can be shared without one printer. |
| LS-5 | confirmed-with-corrections | medium | The two builds are mirror copies and three helpers are dead. The axis is already an argument of eight helpers. |
| LS-6 | confirmed-with-corrections | medium | The chains and the walks are real, with more copies than stated. The methods by kind are safe; the shared walk must leave the read of a node to the SDL backend. |
| LS-7 | weakened | low | A length has roles today, as fields of `WidgetTheme`, by `spacing-rules.md` §3 and D14 of `zoom-and-theme-controls.md`. What remains is the place of the roles, a question for the owner. |
| LS-8 | weakened | low | The form of a style document is decision D2 of `widget-color-design.md`. The override by name loses the typed fields. The unused style types and the hand merges of the charts remain. |
| LS-9 | confirmed | low | The facts hold; both points are open follow-ups of `one-coherent-color-set.md`. |
| LS-10 | confirmed-with-corrections | low | (b) is proved safe: `_prefix_op` gives what `reroot_operation` gives. (a) and (c) hold with limits. |

No finding goes against a settled decision of the owner. LS-4 depends on one that is not made yet (the generic memory of a list), and LS-7 and LS-8 each ask to change a decision of a done plan, which only the owner can do.
