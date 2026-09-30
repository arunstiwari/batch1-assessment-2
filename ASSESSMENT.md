# Assessment: Library Lending API

**Duration:** 4 hours · **Total marks:** 100 · **Individual work**

You are building the backend for a small library. Members browse the catalogue and
borrow books; librarians maintain the catalogue and can see every loan in the system.

Everything is stateless: there are no sessions and no cookies. A caller logs in once,
gets a **JWT**, and sends it on every later request.

---

## 1. What you are given

A runnable but empty Spring Boot project in `starter/`:

| File | What it does |
|---|---|
| `pom.xml` | All dependencies you need are already declared. Do not add more. |
| `LibraryApiApplication.java` | The `@SpringBootApplication` entry point. |
| `application.properties` | H2 datasource, JPA, and the `app.jwt.*` / `app.aop.*` properties. |
| `data.sql` | Seed catalogue. **Your entity mapping must match this schema** (see §3). |
| `LibraryApiApplicationTests` | Context-loads smoke test. Keep it green. |

Check your environment before you start writing code:

```bash
cd starter
./mvnw test          # the smoke test must pass
./mvnw spring-boot:run
```

Use the base package `com.fil.assessment.library` and put your classes in sensible
sub-packages. Nothing else about your internal structure is prescribed.

---

## 2. Users (in-memory, no user table)

Configure these three users with an `InMemoryUserDetailsManager`. Passwords are
plain text in the config for the exercise; encode them with a `PasswordEncoder`.

| Username | Password | Role |
|---|---|---|
| `alice` | `alice123` | `USER` |
| `bob` | `bob123` | `USER` |
| `admin` | `admin123` | `ADMIN` |

Spring Security's `hasRole("ADMIN")` expects the authority `ROLE_ADMIN`. Getting that
prefix wrong is the single most common reason a correct-looking config returns 403.

---

## 3. Data model (JPA)

Two entities, mapped to the exact table and column names below, because `data.sql`
inserts into them. `spring.jpa.hibernate.ddl-auto=create-drop` generates the schema
from your entities, so the names come from your mapping.

**`books`**

| Column | Type | Rules |
|---|---|---|
| `id` | identity | generated primary key |
| `title` | varchar | not null |
| `author` | varchar | not null |
| `isbn` | varchar(20) | not null, **unique** |
| `total_copies` | int | not null |
| `available_copies` | int | not null |
| `version` | bigint | optimistic-locking version column |

**`loans`**

| Column | Type | Rules |
|---|---|---|
| `id` | identity | generated primary key |
| `book_id` | bigint | not null, **many-to-one to `books`, fetched lazily** |
| `borrower` | varchar | not null, the username taken from the JWT |
| `borrowed_at` | timestamp | not null |
| `returned_at` | timestamp | null while the book is still out |

Use Spring Data JPA repositories. Between them you must show **at least one derived
query method** (e.g. `findByAuthorIgnoreCase`) and **at least one explicit `@Query`**.

---

## 4. The API contract

All paths are under `/api`. Request and response bodies are JSON. `ROLE_` prefixes are
omitted below: "USER" means a caller holding `ROLE_USER`.

### 4.1 Authentication — open to everyone

**`POST /api/auth/login`**

```json
{ "username": "admin", "password": "admin123" }
```

`200 OK`:

```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9...",
  "tokenType": "Bearer",
  "expiresInSeconds": 1800,
  "username": "admin",
  "roles": ["ROLE_ADMIN"]
}
```

* Verify the credentials against the in-memory user store — do **not** mint a token for
  an unknown user or a wrong password.
* Wrong credentials → `401`. A blank username or password → `400`.
* Sign with **HS256** using `app.jwt.secret`; expire after `app.jwt.expiry-minutes`.
* The token must carry the username as the subject and the roles as a claim.

Every other endpoint requires `Authorization: Bearer <token>`.
A missing, expired, malformed, or tampered token → `401`. A valid token whose role is
not allowed → `403`.

### 4.2 Catalogue

| Method & path | Who | Success | Notes |
|---|---|---|---|
| `GET /api/books` | USER, ADMIN | `200` | Optional filters: `?author=`, `?title=`, `?available=true`. Filter **in the query**, not in Java. |
| `GET /api/books/{id}` | USER, ADMIN | `200` | Unknown id → `404` |
| `POST /api/books` | ADMIN | `201` + `Location` header | Body validated; duplicate ISBN → `409` |
| `PUT /api/books/{id}` | ADMIN | `200` | Unknown id → `404`; duplicate ISBN → `409` |
| `DELETE /api/books/{id}` | ADMIN | `204` | Unknown id → `404`; copies still on loan → `409` |

Book request body (create and update):

```json
{ "title": "Refactoring", "author": "Martin Fowler", "isbn": "9780201485677", "totalCopies": 2 }
```

Validation rules: `title` and `author` not blank; `isbn` exactly 10 or 13 digits;
`totalCopies` at least 1. A new book starts with `availableCopies == totalCopies`.

Book response:

```json
{ "id": 1, "title": "Clean Code", "author": "Robert C. Martin",
  "isbn": "9780132350884", "totalCopies": 3, "availableCopies": 3 }
```

### 4.3 Loans

| Method & path | Who | Success | Notes |
|---|---|---|---|
| `POST /api/loans` | USER, ADMIN | `201` + `Location` | Borrows for the **caller** |
| `POST /api/loans/{id}/return` | the borrower, or ADMIN | `200` | |
| `GET /api/loans/me` | USER, ADMIN | `200` | Only the caller's loans |
| `GET /api/loans` | **ADMIN only** | `200` | Every borrower's loans |

Borrow request — the borrower is **never** in the body, it comes from the JWT:

```json
{ "bookId": 4 }
```

Loan response:

```json
{ "id": 7, "bookId": 4, "bookTitle": "Designing Data-Intensive Applications",
  "borrower": "alice", "borrowedAt": "2026-09-30T09:15:00Z",
  "returnedAt": null, "status": "ON_LOAN" }
```

Domain rules — each must produce the stated status code, not a `500`:

| Rule | Status |
|---|---|
| Book does not exist | `404` |
| `availableCopies == 0` | `409` |
| The caller already holds an unreturned copy of that book | `409` |
| The caller already has 3 unreturned loans | `409` |
| Returning a loan that is already returned | `409` |
| Returning **someone else's** loan (and the caller is not ADMIN) | `403` |

Borrowing decrements `availableCopies`; returning increments it. Both the loan row and
the book row must change in **one transaction**.

### 4.4 Error responses

Every error — from validation, from your domain rules, and from security — must come
back as JSON in one consistent shape, produced by a single `@RestControllerAdvice`.
Never leak a stack trace or Boot's default whitelabel body.

```json
{ "timestamp": "2026-09-30T09:15:00Z", "status": 400, "error": "Bad Request",
  "message": "Validation failed", "path": "/api/books",
  "fieldErrors": { "isbn": "isbn must be 10 or 13 digits" } }
```

`fieldErrors` is present only for validation failures. You may keep or drop fields, but
the shape must be the same for every error, and `status` must match the HTTP status.

---

## 5. Cross-cutting concerns (AOP)

Write **two** aspects. Both must be Spring AOP (`@Aspect` + `@Component`) — no manual
wrapper classes, no logging statements copy-pasted into every service method.

1. **Audit aspect.** Define your own annotation (e.g. `@Audited("BORROW_BOOK")`) and put
   it on the state-changing service methods: create, update, delete, borrow, return. The
   aspect logs, at `INFO`, **who** performed the action (read the principal from the
   `SecurityContextHolder` — do not add a username parameter to every method), the action
   name, and whether it **succeeded or failed**. A failed call must still be logged, and
   the exception must still reach the caller.

2. **Timing aspect.** Time every public service-layer method and log the duration. Log at
   `WARN` when a call takes longer than `app.aop.slow-call-threshold-ms`, at `DEBUG`
   otherwise.

Between the two, use at least one `@Around` advice and at least one pointcut written
with an `@annotation(...)` or `@within(...)` expression.

---

## 6. Rules and constraints

* **Never expose a JPA entity as a request or response body.** Use DTOs or records.
* Controllers stay thin: HTTP in, HTTP out. Business rules and `@Transactional` belong in
  the service layer.
* Read-only service methods should be `@Transactional(readOnly = true)`.
* Secure the API **twice**: URL rules in the `SecurityFilterChain`, plus method security
  (`@EnableMethodSecurity` with `@PreAuthorize`) on at least the admin-only service
  methods.
* Constructor injection only. No `@Autowired` on fields.
* Do not add dependencies to `pom.xml`, do not change the base package, and do not edit
  `data.sql`.
* Note the Boot 4 dependency names if you look things up: the web starter is
  `spring-boot-starter-webmvc`, JSON is `spring-boot-starter-jackson`, and AOP is
  `spring-boot-starter-aspectj`. They are already in your `pom.xml`.

---

## 7. Marks

| # | Area | Marks |
|---|---|---|
| 1 | REST API design: resources, verbs, status codes, `Location` header, DTOs, validation, one consistent error shape | 25 |
| 2 | JPA: entity mapping to the given schema, the many-to-one association, repositories, derived query + `@Query`, transaction boundaries, copy counting stays correct | 20 |
| 3 | Spring Security: in-memory users and roles, `/api/auth/login`, HS256 issue + verify, stateless JWT filter, URL rules, method security, 401 vs 403 | 30 |
| 4 | AOP: audit aspect with its own annotation and the principal from the security context, timing aspect, correct advice and pointcuts | 15 |
| 5 | Your own tests: at least four meaningful tests, including one that proves a USER cannot reach an ADMIN endpoint | 10 |
| | | **100** |

Partial credit is given per endpoint and per rule, so **ship what works**. A compiling
application with three correct endpoints scores far better than a complete one that does
not start.

---

## 8. Submission

1. `./mvnw clean test` passes.
2. `./mvnw spring-boot:run` starts on port 8080.
3. A `NOTES.md` in the project root with:
   * anything you did not finish, and what you would do next;
   * one paragraph on where you enforced the "you may only return your own loan" rule,
     and why it cannot be a URL rule;
   * any assumption you made.
4. Zip the project **without** `target/`, or push it to a branch and share the link.

Your evaluator will run `assessment/verify.sh` against your running application and read
your log output to check the aspects. You can run it yourself while you work:

```bash
./verify.sh                       # against http://localhost:8080
```

---

## 9. Hints

* Get `POST /api/auth/login` returning a token first, then paste that token into
  `curl -H "Authorization: Bearer ..."`. Everything else depends on it.
* `OncePerRequestFilter` is the right base class for the JWT filter; register it
  `addFilterBefore(..., UsernamePasswordAuthenticationFilter.class)`.
* Do not generate the signing key at start-up. A key from `app.jwt.secret` means the
  tokens you issued a minute ago still verify after a restart.
* A `401` is "I do not know who you are", a `403` is "I know who you are and you may
  not". If you see `403` where you expected `401`, your filter is authenticating a token
  it should have rejected.
* The seed data leaves *Java Concurrency in Practice* fully lent out to `bob`, so you
  have a ready-made `409` case to test borrowing against.
* `spring.jpa.show-sql=true` is already on. Watch the SQL when you write your queries —
  it is the fastest way to catch an N+1 select in `GET /api/loans`.
