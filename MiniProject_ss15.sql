DROP DATABASE IF EXISTS mini_social_network;

CREATE DATABASE mini_social_network;

USE mini_social_network;

-- 1. taoj bảng
CREATE TABLE users (
    user_id int PRIMARY KEY AUTO_INCREMENT,
    username varchar(50) NOT NULL UNIQUE,
    password varchar(255) NOT NULL,
    email varchar(100) NOT NULL UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE posts (
    post_id int PRIMARY KEY AUTO_INCREMENT,
    user_id int NOT NULL,
    content text NOT NULL,
    like_count int DEFAULT 0,
    comment_count int DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_posts_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE RESTRICT,
    FULLTEXT INDEX ft_posts_content (content)
);

CREATE TABLE comments (
    comment_id int PRIMARY KEY AUTO_INCREMENT,
    post_id int NOT NULL,
    user_id int NOT NULL,
    content text NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_comments_post FOREIGN KEY (post_id) REFERENCES posts (post_id) ON DELETE CASCADE,
    CONSTRAINT fk_comments_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE RESTRICT
);

CREATE TABLE likes (
    like_id int PRIMARY KEY AUTO_INCREMENT,
    user_id int NOT NULL,
    post_id int NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_likes_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_likes_post FOREIGN KEY (post_id) REFERENCES posts (post_id) ON DELETE CASCADE,
    CONSTRAINT uq_user_post_like UNIQUE (user_id, post_id)
);

CREATE TABLE friends (
    friendship_id int PRIMARY KEY AUTO_INCREMENT,
    user_id int NOT NULL,
    friend_id int NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'pending',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_friends_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_friends_friend FOREIGN KEY (friend_id) REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT chk_friend_status CHECK (status IN ('pending', 'accepted')),
    CONSTRAINT chk_not_self_friend CHECK (user_id <> friend_id)
);

-- chawnj keest bạn qua lại: A -> B và B -> A
CREATE UNIQUE INDEX uq_friend_pair ON friends ((LEAST (user_id, friend_id)), (GREATEST (user_id, friend_id)));

CREATE TABLE post_logs (
    log_id int PRIMARY KEY AUTO_INCREMENT,
    post_id int,
    user_id int,
    content text,
    deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 2. triggers
DELIMITER //
CREATE TRIGGER trg_likes_after_insert
    AFTER INSERT ON likes
    FOR EACH ROW
BEGIN
    UPDATE posts SET like_count = like_count + 1
WHERE
    post_id = NEW.post_id;

END //
CREATE TRIGGER trg_likes_after_delete
    AFTER DELETE ON likes
    FOR EACH ROW
BEGIN
    UPDATE posts SET like_count = GREATEST (like_count - 1, 0)
    WHERE
        post_id = OLD.post_id;

END //
CREATE TRIGGER trg_comments_after_insert
    AFTER INSERT ON comments
    FOR EACH ROW
BEGIN
    UPDATE posts SET comment_count = comment_count + 1
WHERE
    post_id = NEW.post_id;

END //
CREATE TRIGGER trg_comments_after_delete
    AFTER DELETE ON comments
    FOR EACH ROW
BEGIN
    UPDATE posts SET comment_count = GREATEST (comment_count - 1, 0)
    WHERE
        post_id = OLD.post_id;

END //
CREATE TRIGGER trg_posts_before_delete
    BEFORE DELETE ON posts
    FOR EACH ROW
BEGIN
    INSERT INTO post_logs (post_id,
    user_id,
    content)
VALUES (OLD.post_id,
OLD.user_id,
OLD.content);

END //
DELIMITER ;

-- 3. stored procedures
DELIMITER //
-- F01: Đăng ký thành viên
CREATE PROCEDURE sp_register_user (IN p_username varchar(50), IN p_password varchar(255), IN p_email varchar(100), OUT p_user_id int)
BEGIN
    IF EXISTS (
    SELECT
        1
    FROM
        users
    WHERE
        username = p_username) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Username already exists';

END IF;

IF EXISTS (
    SELECT
        1
    FROM
        users
    WHERE
        email = p_email) THEN
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Email already exists';

END IF;

INSERT INTO users (username, password, email)
    VALUES (p_username, p_password, p_email);

SET p_user_id = LAST_INSERT_ID ();

END //
-- F02: Đăng bài viết
CREATE PROCEDURE sp_create_post (IN p_user_id int, IN p_content text, OUT p_post_id int)
BEGIN
    IF NOT EXISTS (
    SELECT
        1
    FROM
        users
    WHERE
        user_id = p_user_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User does not exist';

END IF;

INSERT INTO posts (user_id, content)
    VALUES (p_user_id, p_content);

SET p_post_id = LAST_INSERT_ID ();

END //
-- F03: Thích bài viết
CREATE PROCEDURE sp_like_post (IN p_user_id int, IN p_post_id int)
BEGIN
    IF NOT EXISTS (
    SELECT
        1
    FROM
        users
    WHERE
        user_id = p_user_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User does not exist';

END IF;

IF NOT EXISTS (
    SELECT
        1
    FROM
        posts
    WHERE
        post_id = p_post_id) THEN
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Post does not exist';

END IF;

INSERT INTO likes (user_id, post_id)
    VALUES (p_user_id, p_post_id);

END //
-- F03: Hủy thích bài viết
CREATE PROCEDURE sp_unlike_post (IN p_user_id int, IN p_post_id int)
BEGIN
    DELETE FROM likes
    WHERE user_id = p_user_id AND post_id = p_post_id;

IF ROW_COUNT () = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Like does not exist';

END IF;

END //
-- Bình luận bài viết
CREATE PROCEDURE sp_create_comment (IN p_user_id int, IN p_post_id int, IN p_content text, OUT p_comment_id int)
BEGIN
    IF NOT EXISTS (
    SELECT
        1
    FROM
        users
    WHERE
        user_id = p_user_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User does not exist';

END IF;

IF NOT EXISTS (
    SELECT
        1
    FROM
        posts
    WHERE
        post_id = p_post_id) THEN
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Post does not exist';

END IF;

INSERT INTO comments (post_id, user_id, content)
    VALUES (p_post_id, p_user_id, p_content);

SET p_comment_id = LAST_INSERT_ID ();

END //
-- F04: Gửi lời mời kết bạn
CREATE PROCEDURE sp_send_friend_request (IN p_user_id int, IN p_friend_id int)
BEGIN
    IF p_user_id = p_friend_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot send friend request to yourself';

END IF;

IF NOT EXISTS (
    SELECT
        1
    FROM
        users
    WHERE
        user_id = p_user_id) THEN
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sender does not exist';

END IF;

IF NOT EXISTS (
    SELECT
        1
    FROM
        users
    WHERE
        user_id = p_friend_id) THEN
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Receiver does not exist';

END IF;

INSERT INTO friends (user_id, friend_id, status)
    VALUES (p_user_id, p_friend_id, 'pending');

END //
-- F05: Chấp nhận lời mời kết bạn
CREATE PROCEDURE sp_accept_friend_request (IN p_user_id int, IN p_friend_id int)
BEGIN
    UPDATE
        friends SET
            status = 'accepted'
        WHERE
            user_id = p_friend_id AND friend_id = p_user_id AND status = 'pending';

IF ROW_COUNT () = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pending friend request does not exist';

END IF;

END //
-- F05: Hủy lời mời hoặc hủy kết bạn
CREATE PROCEDURE sp_remove_friend (IN p_user_id int, IN p_friend_id int)
BEGIN
    DELETE FROM friends
    WHERE LEAST (user_id, friend_id) = LEAST (p_user_id, p_friend_id) AND GREATEST (user_id, friend_id) = GREATEST (p_user_id, p_friend_id);

IF ROW_COUNT () = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Friend relationship does not exist';

END IF;

END //
-- F07: Tìm kiếm bài viết theo từ khóa
CREATE PROCEDURE sp_search_posts (IN p_keyword varchar(255))
BEGIN
    SELECT
        p.post_id, p.user_id, u.username, p.content, p.like_count, p.comment_count, p.created_at
    FROM
        posts p
        JOIN users u ON u.user_id = p.user_id
    WHERE
        MATCH (p.content) AGAINST (p_keyword IN
        NATURAL
        LANGUAGE MODE
)
        ORDER BY
            p.created_at DESC;

END //
-- F08: Báo cáo hoạt động của user
CREATE PROCEDURE sp_user_activity_report (IN p_user_id int)
BEGIN
    SELECT
        u.user_id, u.username, COUNT(DISTINCT p.post_id) AS total_posts,
            COALESCE(SUM(p.like_count), 0) AS total_likes,
            COALESCE(SUM(p.comment_count), 0) AS total_comments
        FROM
            users u
        LEFT JOIN posts p ON p.user_id = u.user_id
    WHERE
        u.user_id = p_user_id
    GROUP BY
        u.user_id,
        u.username;

END //
-- F09: Gợi ý kết bạn bằng CTE
CREATE PROCEDURE sp_suggest_friends (IN p_user_id int)
BEGIN
    WITH accepted_friends AS (
        SELECT
            friend_id AS user_friend_id
        FROM
            friends
        WHERE
            user_id = p_user_id
            AND status = 'accepted'
        UNION
        SELECT
            user_id AS user_friend_id
        FROM
            friends
        WHERE
            friend_id = p_user_id
            AND status = 'accepted'
),
friends_of_friends AS (
    SELECT
        CASE WHEN f.user_id = af.user_friend_id THEN
            f.friend_id
        ELSE
            f.user_id
        END AS suggested_user_id
    FROM
        friends f
        JOIN accepted_friends af ON f.user_id = af.user_friend_id
            OR f.friend_id = af.user_friend_id
    WHERE
        f.status = 'accepted'
)
SELECT DISTINCT
    u.user_id,
    u.username,
    u.email
FROM
    friends_of_friends fof
    JOIN users u ON u.user_id = fof.suggested_user_id
WHERE
    fof.suggested_user_id <> p_user_id
    AND fof.suggested_user_id NOT IN (
        SELECT
            user_friend_id
        FROM
            accepted_friends)
    AND NOT EXISTS (
        SELECT
            1
        FROM
            friends f
        WHERE
            LEAST (f.user_id, f.friend_id) = LEAST (p_user_id, fof.suggested_user_id)
            AND GREATEST (f.user_id, f.friend_id) = GREATEST (p_user_id, fof.suggested_user_id));

END //
-- F10: Xóa bài viết của chính mình bằng Transaction
CREATE PROCEDURE sp_delete_post (IN p_user_id int, IN p_post_id int)
BEGIN
DECLARE
    EXIT HANDLER FOR SQLEXCEPTION
BEGIN
    ROLLBACK;
    RESIGNAL;

END;

START TRANSACTION;

IF NOT EXISTS (
    SELECT
        1
    FROM
        posts
    WHERE
        post_id = p_post_id
        AND user_id = p_user_id) THEN
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Post does not exist or permission denied';

END IF;

DELETE FROM posts
WHERE post_id = p_post_id
    AND user_id = p_user_id;

COMMIT;

END //
-- F11: Xóa tài khoản user an toàn bằng Transaction
CREATE PROCEDURE sp_delete_user_account (IN p_user_id int)
BEGIN
DECLARE
    EXIT HANDLER FOR SQLEXCEPTION
BEGIN
    ROLLBACK;
    RESIGNAL;

END;

START TRANSACTION;

IF NOT EXISTS (
    SELECT
        1
    FROM
        users
    WHERE
        user_id = p_user_id) THEN
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'User does not exist';

END IF;

-- Xóa likes do user tạo
DELETE FROM likes
WHERE user_id = p_user_id;

-- Xóa comments do user tạo
DELETE FROM comments
WHERE user_id = p_user_id;

-- Xóa quan hệ bạn bè liên quan tới user
DELETE FROM friends
WHERE user_id = p_user_id
    OR friend_id = p_user_id;

-- Xóa posts của user
-- Likes/comments thuộc post sẽ tự xóa theo ON DELETE CASCADE
DELETE FROM posts
WHERE user_id = p_user_id;

-- Xóa user cuối cùng
DELETE FROM users
WHERE user_id = p_user_id;

COMMIT;

END //
DELIMITER ;

-- 4. VIEWS
CREATE VIEW v_user_profiles AS
SELECT
    u.user_id,
    u.username,
    u.email,
    u.created_at,
    COUNT(DISTINCT p.post_id) AS total_posts,
    COUNT(DISTINCT CASE WHEN f.status = 'accepted' THEN
            f.friendship_id
        END) AS total_friend_records
FROM
    users u
    LEFT JOIN posts p ON p.user_id = u.user_id
    LEFT JOIN friends f ON f.user_id = u.user_id
        OR f.friend_id = u.user_id
GROUP BY
    u.user_id,
    u.username,
    u.email,
    u.created_at;

CREATE VIEW v_user_activity_report AS
SELECT
    u.user_id,
    u.username,
    COUNT(DISTINCT p.post_id) AS total_posts,
    COALESCE(SUM(p.like_count), 0) AS total_likes,
    COALESCE(SUM(p.comment_count), 0) AS total_comments
FROM
    users u
    LEFT JOIN posts p ON p.user_id = u.user_id
GROUP BY
    u.user_id,
    u.username;

-- 5. Dữ liệu mãu
INSERT INTO users (username, password, email)
VALUES
    ('alice', 'hashed_password_1', 'alice@example.com'),
    ('bob', 'hashed_password_2', 'bob@example.com'),
    ('charlie', 'hashed_password_3', 'charlie@example.com'),
    ('david', 'hashed_password_4', 'david@example.com');

INSERT INTO posts (user_id, content)
VALUES
    (1, 'Hello world, this is my first social network post'),
    (2, 'Learning MySQL trigger and transaction is very useful'),
    (3, 'Database centric application with stored procedure');

INSERT INTO comments (post_id, user_id, content)
VALUES
    (1, 2, 'Nice post Alice'),
    (1, 3, 'Welcome to the network'),
    (2, 1, 'Good topic bro');

INSERT INTO likes (user_id, post_id)
VALUES
    (2, 1),
    (3, 1),
    (1, 2),
    (4, 2);

INSERT INTO friends (user_id, friend_id, status)
VALUES
    (1, 2, 'accepted'),
    (2, 3, 'accepted'),
    (3, 4, 'pending');

-- 6. test queries
-- Kiểm tra trigger like_count/comment_count
SELECT
    *
FROM
    posts;

-- Test chống like trùng
-- Dòng này sẽ lỗi vì user 2 đã like post 1
-- CALL sp_like_post(2, 1);
-- Test gửi lời mời đảo chiều
-- Dòng này sẽ lỗi vì đã tồn tại quan hệ 1 - 2
-- CALL sp_send_friend_request(2, 1);
-- Test tìm kiếm full-text
CALL sp_search_posts ('MySQL transaction');

-- Test báo cáo hoạt động
CALL sp_user_activity_report (1);

-- Test view profile
SELECT
    *
FROM
    v_user_profiles;

-- Test gợi ý bạn bè cho Alice
CALL sp_suggest_friends (1);

-- Test xóa bài viết
-- CALL sp_delete_post(1, 1);
-- Test xóa tài khoản an toàn
-- CALL sp_delete_user_account(4);
