-- Seed catalogue. version = 0 because the @Version column is not nullable.
insert into books (title, author, isbn, total_copies, available_copies, version) values
  ('Clean Code',                  'Robert C. Martin',  '9780132350884', 3, 3, 0),
  ('Effective Java',              'Joshua Bloch',      '9780134685991', 2, 2, 0),
  ('Spring in Action',            'Craig Walls',       '9781617297571', 1, 1, 0),
  ('Designing Data-Intensive Applications', 'Martin Kleppmann', '9781449373320', 2, 2, 0),
  ('Java Concurrency in Practice','Brian Goetz',       '9780321349606', 1, 0, 0);

-- Book 5 is fully lent out to bob: gives every trainee a ready-made
-- "409 Conflict - no copies available" case to test against.
insert into loans (book_id, borrower, borrowed_at, returned_at) values
  (5, 'bob', timestamp '2026-09-20 10:15:00', null);
