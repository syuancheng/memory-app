# REST API 参考

Base URL：`/api`（`/healthz` 除外）。共 33 个端点。

## 通用约定

**鉴权**：需要鉴权的端点要求 `Authorization: Bearer <session_token>`。失败一律 **401** `{"error":"unauthorized"}`，不区分令牌过期、被撤销还是不存在。

**错误响应**恒为：

```json
{"error": "具体描述"}
```

**⚠️ 请求体多传任何字段都会 400。** 解码器开了 `DisallowUnknownFields()`，未知字段直接报错：

```json
{"error": "invalid json"}
```

**CORS**：`Access-Control-Allow-Origin: *`，`OPTIONS` 返回 204。

### 状态码是怎么决定的

多数 auth 相关端点走 `writeAuthError`，它**基于错误文案的字符串匹配**分流：

| 条件 | 状态码 |
|---|---|
| 文案含 `"unauthorized"` 或 `"invalid session"` | 401 |
| 文案含 `"not configured"` | 501 |
| 其余 | 400 |

判断按顺序覆盖，401 那条优先级最高。

⚠️ **这是脆弱契约**：改一句错误文案就可能改变 HTTP 状态码。比如 `"email delivery is not configured"` 之所以返回 501 而不是 400，全靠 `"not configured"` 这个子串。源码里有注释提醒。

---

## 健康检查

### `GET /healthz`

无需鉴权。→ 200 `{"status":"ok"}`

---

## 认证

### `POST /api/auth/request-code`

发送登录验证码。无需鉴权。

```json
{"email": "me@example.com"}
```

→ 200 `{"status":"sent"}`

| 错误 | 码 |
|---|---|
| `invalid json` | 400 |
| `email is required` / `invalid email` | 400 |
| `please wait before requesting another code` | 400 |
| `email delivery is not configured` | 501 |
| `could not send the verification email, please try again` | 400 |

---

### `POST /api/auth/verify-code`

验证码登录。**未知邮箱会自动创建账号。** 无需鉴权。

```json
{"email": "me@example.com", "code": "123456"}
```

→ 200

```json
{
  "user": {"id": "...", "email": "...", "name": "...", "provider": "email"},
  "session_token": "cdly_...",
  "is_new_user": false,
  "has_password": true
}
```

`is_new_user` 表示本次顺带创建了账号；`has_password` 决定客户端是否展示密码登录入口。

| 错误 | 码 |
|---|---|
| `verification code is invalid or expired` | 400 |
| `verification code attempts exceeded` | 400 |
| 查询 has_password 失败 | **500** |

---

### `POST /api/auth/login-password`

密码登录。无需鉴权。

```json
{"email": "me@example.com", "password": "..."}
```

→ 200 同上结构（`has_password` 恒 true，`is_new_user` 恒 false）

| 错误 | 码 |
|---|---|
| `invalid email or password` | 400 |
| `too many failed attempts, please try again later or sign in with a code` | 400 |

⚠️ 第一条对「邮箱不存在」「密码错误」「从未设过密码」返回**完全相同**的文案，见 [auth.md](auth.md#三重防枚举)。

---

### `POST /api/auth/password`

设置或修改密码。**需要鉴权**，不要求旧密码。

```json
{"password": "at-least-8-chars"}
```

→ 200 `{"status":"updated"}`

| 错误 | 码 |
|---|---|
| `password must be at least 8 characters` | 400 |
| `password is too long`（> 72 字节） | 400 |

---

### `POST /api/auth/password/reset-code`

发送重置密码验证码。无需鉴权。

```json
{"email": "me@example.com"}
```

→ 200 `{"status":"sent"}`

⚠️ **邮箱不存在时也返回 200**，不发信不落库（防账号枚举）。

---

### `POST /api/auth/password/reset`

用验证码重置密码。无需鉴权。**会撤销该用户全部现有会话。**

```json
{"email": "...", "code": "123456", "password": "new-password"}
```

→ 200 `{"status":"updated"}`

---

### `POST /api/auth/apple`

Apple 登录。无需鉴权。

```json
{
  "identity_token": "...",
  "authorization_code": "...",
  "nonce": "...",
  "full_name": "...",
  "email": "..."
}
```

→ 200 同 verify-code 结构（`is_new_user` / `has_password` 恒 false）

`"apple ... is not configured"` 类错误 → **501**。

---

### `GET /api/auth/me`

当前用户。**需要鉴权**。

→ 200 `{"user": {...}, "is_new_user": false, "has_password": false}`

⚠️ `has_password` 在这个端点恒为 false，**不反映真实状态**——它只在 verify-code / login-password 里被正确填充。

---

### `POST /api/auth/logout`

撤销当前会话。**需要鉴权**，不读请求体。

→ 200 `{"status":"logged_out"}`

---

## 账号

### `PATCH /api/account`

修改显示名。**需要鉴权**。

```json
{"display_name": "新名字"}
```

→ 200 `{"user": {...}}`

| 错误 | 码 |
|---|---|
| `name is required` | 400 |
| `name is too long`（> 60 字符） | 400 |

⚠️ CORS 的 `Access-Control-Allow-Methods` 里**没有列 PATCH**，但这个端点确实是 PATCH。浏览器端跨域调用会被预检拦住；iOS 不走 CORS 所以没问题。

---

### `POST /api/account/delete-code`

发送注销账号验证码。**需要鉴权**，不读请求体。

→ 200 `{"status":"sent"}`；Apple 账号返回 `{"status":"not_required"}`

---

### `DELETE /api/account`

注销账号。**需要鉴权**。

```json
{"email": "me@example.com", "code": "123456"}
```

Apple 账号无需验证码。`email` 留空会自动填当前用户邮箱；填了则必须与当前账号匹配。

→ 200 `{"status":"deleted"}`

软删除：subjects / tags / cards 全部软删，会话与 provider token 撤销，users 置 `deleted_at`。**`review_events` 与 `identities` 保留**。

---

## 用户概览

### `GET /api/me/summary`

**需要鉴权**。

→ 200

```json
{
  "user": {"name": "...", "email": "...", "provider": "email"},
  "total_cards": 23,
  "due_count": 19,
  "mastered_count": 0,
  "reviewed_today": 7,
  "total_reviewed": 105,
  "current_streak": 6,
  "recent_activity": [{"date": "2026-08-10", "count": 4}]
}
```

`recent_activity` **恒为 365 条**，按日升序，无活动的日期 `count` 为 0。窗口取 365 天是为了同时覆盖 Me 页 16 周热力图（112 天）与成就页可回翻 12 个月。

`current_streak` 从数组尾部往前数连续非零天数。

用户不存在 → 404。

---

## MCP 个人访问令牌

### `GET /api/mcp/tokens`

**需要鉴权**。→ 200 `[]`（数组）

```json
[{"id": "...", "name": "Claude Desktop", "created_at": "2026-08-10T09:47:39Z", "last_used_at": null}]
```

明文不返回。

---

### `POST /api/mcp/tokens`

**需要鉴权**。

```json
{"name": "Claude Desktop"}
```

→ **201**，`token` 字段含明文，**仅此一次**：

```json
{"id": "...", "name": "...", "created_at": "...", "last_used_at": null, "token": "mcp_..."}
```

名称留空时后端填 `"MCP client"`。

⚠️ 这个端点**忽略 JSON 解析错误**（`_ = readJSON(...)`），空 body 或非法 JSON 都不会 400，会当作没传名字。

---

### `DELETE /api/mcp/tokens/{tokenID}`

**需要鉴权**。只能撤销自己的令牌。

→ 200 `{"status":"revoked"}`；任何失败（含别人的令牌）→ **404**

---

## Subjects

以下全部**需要鉴权**。

### `GET /api/subjects`

→ 200，按 name 升序

```json
[{"id": "...", "name": "English", "card_count": 5, "due_count": 4}]
```

`due_count` 口径：`due_at <= now()` 且 `status NOT IN ('deleted','mastered')`。

### `POST /api/subjects`

`{"name": "English"}` → **201** `{"id":..., "name":..., "card_count":0, "due_count":0}`

同名冲突 → 400（会透出原始 Postgres 错误文本）。

### `PUT /api/subjects/{subjectID}`

`{"name": "..."}` → 200。不存在 → **404** `subject not found`

### `DELETE /api/subjects/{subjectID}`

→ 200 `{"status":"deleted"}`。不存在 → 404

**级联**：软删该 subject 的 tags 与 cards，对应 review_states 置 `'deleted'`（一个事务）。

---

## Sets（表名 tags）

### `GET /api/subjects/{subjectID}/tags`

→ 200

```json
[{"id": "...", "subject_id": "...", "name": "Polite requests", "card_count": 4, "due_count": 4}]
```

⚠️ 别人的 subjectID 返回空数组，不报错。

### `POST /api/subjects/{subjectID}/tags`

`{"name": "..."}` → **201**。subject 不存在或不属于自己 → **404** `subject not found`

### `PUT /api/subjects/{subjectID}/tags/{tagID}`

`{"name": "..."}` → 200。不存在 → **404** `set not found`（注意文案是 set 不是 tag）

### `DELETE /api/subjects/{subjectID}/tags/{tagID}`

→ 200 `{"status":"deleted"}`

⚠️ **级联软删挂在该 tag 下的所有卡片**，即使那些卡片还挂在别的 tag 上。

---

## Cards

### `GET /api/cards`

Query 参数：

| 参数 | 说明 |
|---|---|
| `subject_id` | 按科目过滤 |
| `tag_ids` | 逗号分隔 |
| `search` | 对 front_text / answer_text 做 ILIKE 模糊匹配 |

⚠️ **limit 硬编码 200，不可通过参数调整。**

→ 200，排序 `due_at ASC, created_at DESC`

```json
[{
  "id": "...", "subject_id": "...", "subject_name": "English",
  "tags": [{"id":"...", "subject_id":"...", "name":"...", "card_count":0, "due_count":0}],
  "card_type": "sentence",
  "direction": "zh_to_en",
  "front_text": "有没有可能明天之前拿到？",
  "answer_text": "Is there any chance we could have it by tomorrow?",
  "grammar_phrases": [{"text": "...", "note": "..."}],
  "answer_tokens": [{"text": "Is", "index": 0}],
  "created_at": "...", "updated_at": "..."
}]
```

⚠️ 嵌套 `tags` 里的 `card_count` / `due_count` **恒为 0**，不要依赖。

### `POST /api/cards`

```json
{
  "subject_id": "...",
  "tag_ids": ["..."],
  "card_type": "sentence",
  "direction": "zh_to_en",
  "front_text": "...",
  "answer_text": "...",
  "grammar_phrases": [{"text": "...", "note": "..."}]
}
```

→ **201**，返回完整 Card。

⚠️ **`direction` 会被忽略**——后端一律用 `DetectDirection(front_text)` 覆盖。字段保留只为兼容，传什么都不影响结果。

⚠️ `card_type` 经归一化：不是 `"word"` 的一切值（含空串和历史值 `speaking_expression`、`grammar`）都变成 `"sentence"`。

**所有错误一律 400**，包括 `subject not found` / `set not found`：

| 错误 |
|---|
| `subject_id is required` / `front_text is required` / `answer_text is required` |
| `at least one tag_id is required` |
| `subject not found` / `set not found` |

### `GET /api/cards/{cardID}`

→ 200 单个 Card。不存在或不属于自己 → **404** `card not found`

### `PUT /api/cards/{cardID}`

全量覆盖，请求体同 POST。标签是先全删再重插。

→ 200 完整 Card

⚠️ **不一致**：这个端点的 `card not found` 返回 **400**，而 GET / DELETE 同样情况返回 404。

### `DELETE /api/cards/{cardID}`

→ 200 `{"status":"deleted"}`。不存在 → 404

软删卡片 + review_states 置 `'deleted'`。

### `POST /api/cards/{cardID}/master`

标记为已掌握：`status='mastered'`，`due_at = now() + 100 年`。

→ 200 `{"status":"mastered"}`。不存在 → 404

### `GET /api/cards/{cardID}/review-preview`

四档评分各自的下次间隔。→ 200，**固定 4 个元素，顺序恒为 again / hard / good / easy**：

```json
[{"grade": "again", "interval_seconds": 60, "due_at": "..."}]
```

review_state 不存在 → **404** `review state not found`

---

## 复习

### `GET /api/review/due`

Query：`subject_id`、`tag_ids`（CSV）、`limit`

⚠️ `limit` **默认 30，有效范围 1–100**。超出范围时**静默回落 30**，不报错。

过滤：`due_at <= now()` 且 `status NOT IN ('deleted','mastered')`

→ 200 Card 数组

### `POST /api/review/result`

提交复习结果。

```json
{
  "card_id": "...",
  "mode": "review",
  "rating": "good",
  "revealed_tokens_count": 3,
  "total_tokens_count": 10
}
```

`mode` 留空默认 `"review"`，**无枚举校验**，传任何字符串都会被存进 `review_events`。

`rating` 必须是 `again` / `hard` / `good` / `easy`，否则 400 `rating must be again, hard, good, or easy`。

→ 200 更新后的 ReviewState：

```json
{
  "card_id": "...", "status": "review", "ease": 2.35, "interval_days": 3,
  "due_at": "...", "review_count": 1, "lapse_count": 0,
  "last_reviewed_at": "...", "mastered_at": null
}
```

卡片不存在或不属于自己 → **404** `review state not found`

⚠️ `revealed_tokens_count` / `total_tokens_count` **不做任何校验**，可以是负数或任意值，只影响自己的统计。

---

## 已知不一致

同类情况在不同端点返回不同状态码，记录如下（都是历史遗留，改动会破坏客户端）：

| 情况 | 端点 | 状态码 |
|---|---|---|
| card not found | `GET/DELETE /cards/{id}` | 404 |
| card not found | **`PUT /cards/{id}`** | **400** |
| subject not found | `PUT/DELETE /subjects/{id}` | 404 |
| subject not found | **`POST /cards`** | **400** |
| 令牌不存在 | `DELETE /mcp/tokens/{id}` | 404（DB 错误也是 404） |

其他：

- CORS 的 `Allow-Methods` 缺 `PATCH`，但 `PATCH /account` 存在
- `POST /mcp/tokens` 忽略 JSON 解析错误
- `GET /auth/me` 的 `has_password` 恒 false，不反映真实状态
