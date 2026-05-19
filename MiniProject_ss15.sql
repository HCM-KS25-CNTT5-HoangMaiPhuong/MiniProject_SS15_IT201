DROP DATABASE IF EXISTS mini_social_network;

CREATE DATABASE mini_social_network
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE mini_social_network;

CREATE TABLE users (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE posts (
    post_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_posts_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT,
    FULLTEXT INDEX ft_posts_content(content)
);

CREATE INDEX idx_posts_user
ON posts(user_id);

CREATE TABLE comments (
    comment_id INT PRIMARY KEY AUTO_INCREMENT,
    post_id INT NOT NULL,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_comments_post
        FOREIGN KEY (post_id)
        REFERENCES posts(post_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_comments_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT
);

CREATE INDEX idx_comments_post
ON comments(post_id);

CREATE INDEX idx_comments_user
ON comments(user_id);

CREATE TABLE likes (
    like_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    post_id INT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_likes_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_likes_post
        FOREIGN KEY (post_id)
        REFERENCES posts(post_id)
        ON DELETE CASCADE,
    CONSTRAINT uq_user_post_like
        UNIQUE(user_id, post_id)
);

CREATE INDEX idx_likes_post
ON likes(post_id);

CREATE TABLE friends (
    friendship_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    friend_id INT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_friends_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_friends_friend
        FOREIGN KEY (friend_id)
        REFERENCES users(user_id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_friend_status
        CHECK(status IN ('pending', 'accepted')),
    CONSTRAINT chk_not_self_friend
        CHECK(user_id <> friend_id)
);

CREATE INDEX idx_friends_status
ON friends(status);

CREATE UNIQUE INDEX uq_friend_pair
ON friends(
    (LEAST(user_id, friend_id)),
    (GREATEST(user_id, friend_id))
);

CREATE TABLE post_logs (
    log_id INT PRIMARY KEY AUTO_INCREMENT,
    post_id INT,
    user_id INT,
    content TEXT,
    deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

DELIMITER //

CREATE TRIGGER trg_likes_after_insert
AFTER INSERT ON likes
FOR EACH ROW
BEGIN
    UPDATE posts
    SET like_count = like_count + 1
    WHERE post_id = NEW.post_id;
END //

CREATE TRIGGER trg_likes_after_delete
AFTER DELETE ON likes
FOR EACH ROW
BEGIN
    UPDATE posts
    SET like_count = GREATEST(like_count - 1, 0)
    WHERE post_id = OLD.post_id;
END //

CREATE TRIGGER trg_comments_after_insert
AFTER INSERT ON comments
FOR EACH ROW
BEGIN
    UPDATE posts
    SET comment_count = comment_count + 1
    WHERE post_id = NEW.post_id;
END //

CREATE TRIGGER trg_comments_after_delete
AFTER DELETE ON comments
FOR EACH ROW
BEGIN
    UPDATE posts
    SET comment_count = GREATEST(comment_count - 1, 0)
    WHERE post_id = OLD.post_id;
END //

CREATE TRIGGER trg_posts_before_delete
BEFORE DELETE ON posts
FOR EACH ROW
BEGIN
    INSERT INTO post_logs(post_id, user_id, content)
    VALUES(OLD.post_id, OLD.user_id, OLD.content);
END //

CREATE PROCEDURE sp_register_user(
    IN p_username VARCHAR(50),
    IN p_password VARCHAR(255),
    IN p_email VARCHAR(100),
    OUT p_user_id INT
)
BEGIN

    IF EXISTS (
        SELECT 1
        FROM users
        WHERE username = p_username
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ten dang nhap da ton tai';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM users
        WHERE email = p_email
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Email da ton tai';
    END IF;

    INSERT INTO users(username, password, email)
    VALUES(p_username, p_password, p_email);

    SET p_user_id = LAST_INSERT_ID();

END //

CREATE PROCEDURE sp_create_post(
    IN p_user_id INT,
    IN p_content TEXT,
    OUT p_post_id INT
)
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM users
        WHERE user_id = p_user_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nguoi dung khong ton tai';
    END IF;

    INSERT INTO posts(user_id, content)
    VALUES(p_user_id, p_content);

    SET p_post_id = LAST_INSERT_ID();

END //

CREATE PROCEDURE sp_like_post(
    IN p_user_id INT,
    IN p_post_id INT
)
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM users
        WHERE user_id = p_user_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nguoi dung khong ton tai';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM posts
        WHERE post_id = p_post_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Bai viet khong ton tai';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM likes
        WHERE user_id = p_user_id
        AND post_id = p_post_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ban da thich bai viet nay';
    END IF;

    INSERT INTO likes(user_id, post_id)
    VALUES(p_user_id, p_post_id);

END //

CREATE PROCEDURE sp_unlike_post(
    IN p_user_id INT,
    IN p_post_id INT
)
BEGIN

    DELETE FROM likes
    WHERE user_id = p_user_id
    AND post_id = p_post_id;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Luot thich khong ton tai';
    END IF;

END //

CREATE PROCEDURE sp_create_comment(
    IN p_user_id INT,
    IN p_post_id INT,
    IN p_content TEXT,
    OUT p_comment_id INT
)
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM users
        WHERE user_id = p_user_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nguoi dung khong ton tai';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM posts
        WHERE post_id = p_post_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Bai viet khong ton tai';
    END IF;

    INSERT INTO comments(post_id, user_id, content)
    VALUES(p_post_id, p_user_id, p_content);

    SET p_comment_id = LAST_INSERT_ID();

END //

CREATE PROCEDURE sp_send_friend_request(
    IN p_user_id INT,
    IN p_friend_id INT
)
BEGIN

    IF p_user_id = p_friend_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Khong the gui loi moi ket ban cho chinh minh';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM users
        WHERE user_id = p_user_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nguoi gui khong ton tai';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM users
        WHERE user_id = p_friend_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nguoi nhan khong ton tai';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM friends
        WHERE LEAST(user_id, friend_id) = LEAST(p_user_id, p_friend_id)
        AND GREATEST(user_id, friend_id) = GREATEST(p_user_id, p_friend_id)
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Quan he ban be da ton tai';
    END IF;

    INSERT INTO friends(user_id, friend_id, status)
    VALUES(p_user_id, p_friend_id, 'pending');

END //

CREATE PROCEDURE sp_accept_friend_request(
    IN p_user_id INT,
    IN p_friend_id INT
)
BEGIN

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM users
        WHERE user_id = p_user_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nguoi dung khong ton tai';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM users
        WHERE user_id = p_friend_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ban be khong ton tai';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM friends
        WHERE user_id = p_friend_id
        AND friend_id = p_user_id
        AND status = 'pending'
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Khong ton tai loi moi ket ban dang cho';
    END IF;

    UPDATE friends
    SET status = 'accepted'
    WHERE user_id = p_friend_id
    AND friend_id = p_user_id
    AND status = 'pending';

    COMMIT;

END //

CREATE PROCEDURE sp_remove_friend(
    IN p_user_id INT,
    IN p_friend_id INT
)
BEGIN

    DELETE FROM friends
    WHERE LEAST(user_id, friend_id) = LEAST(p_user_id, p_friend_id)
    AND GREATEST(user_id, friend_id) = GREATEST(p_user_id, p_friend_id);

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Quan he ban be khong ton tai';
    END IF;

END //

CREATE PROCEDURE sp_search_posts(
    IN p_keyword VARCHAR(255)
)
BEGIN

    SELECT
        p.post_id,
        p.user_id,
        u.username,
        p.content,
        p.like_count,
        p.comment_count,
        p.created_at
    FROM posts p
    JOIN users u
        ON u.user_id = p.user_id
    WHERE MATCH(p.content)
    AGAINST(p_keyword IN NATURAL LANGUAGE MODE)
    ORDER BY p.created_at DESC;

END //

CREATE PROCEDURE sp_user_activity_report(
    IN p_user_id INT
)
BEGIN

    SELECT
        u.user_id,
        u.username,
        COUNT(DISTINCT p.post_id) AS total_posts,
        COALESCE(SUM(p.like_count), 0) AS total_likes,
        COALESCE(SUM(p.comment_count), 0) AS total_comments
    FROM users u
    LEFT JOIN posts p
        ON p.user_id = u.user_id
    WHERE u.user_id = p_user_id
    GROUP BY
        u.user_id,
        u.username;

END //

CREATE PROCEDURE sp_suggest_friends(
    IN p_user_id INT
)
BEGIN

    WITH accepted_friends AS (
        SELECT friend_id AS user_friend_id
        FROM friends
        WHERE user_id = p_user_id
        AND status = 'accepted'

        UNION

        SELECT user_id AS user_friend_id
        FROM friends
        WHERE friend_id = p_user_id
        AND status = 'accepted'
    ),
    friends_of_friends AS (
        SELECT
            CASE
                WHEN f.user_id = af.user_friend_id
                THEN f.friend_id
                ELSE f.user_id
            END AS suggested_user_id
        FROM friends f
        JOIN accepted_friends af
            ON f.user_id = af.user_friend_id
            OR f.friend_id = af.user_friend_id
        WHERE f.status = 'accepted'
    )

    SELECT DISTINCT
        u.user_id,
        u.username,
        u.email
    FROM friends_of_friends fof
    JOIN users u
        ON u.user_id = fof.suggested_user_id
    WHERE fof.suggested_user_id <> p_user_id
    AND fof.suggested_user_id NOT IN (
        SELECT user_friend_id
        FROM accepted_friends
    )
    AND NOT EXISTS (
        SELECT 1
        FROM friends f
        WHERE LEAST(f.user_id, f.friend_id)
            = LEAST(p_user_id, fof.suggested_user_id)
        AND GREATEST(f.user_id, f.friend_id)
            = GREATEST(p_user_id, fof.suggested_user_id)
    );

END //

CREATE PROCEDURE sp_delete_post(
    IN p_user_id INT,
    IN p_post_id INT
)
BEGIN

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM posts
        WHERE post_id = p_post_id
        AND user_id = p_user_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Bai viet khong ton tai hoac ban khong co quyen xoa';
    END IF;

    DELETE FROM posts
    WHERE post_id = p_post_id
    AND user_id = p_user_id;

    COMMIT;

END //

CREATE PROCEDURE sp_delete_user_account(
    IN p_user_id INT
)
BEGIN

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM users
        WHERE user_id = p_user_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nguoi dung khong ton tai';
    END IF;

    DELETE FROM likes
    WHERE user_id = p_user_id;

    DELETE FROM comments
    WHERE user_id = p_user_id;

    DELETE FROM friends
    WHERE user_id = p_user_id
    OR friend_id = p_user_id;

    DELETE FROM posts
    WHERE user_id = p_user_id;

    DELETE FROM users
    WHERE user_id = p_user_id;

    COMMIT;

END //

DELIMITER ;