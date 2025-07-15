-- Database schema for laundry_pos
CREATE DATABASE IF NOT EXISTS laundry_pos;
USE laundry_pos;

-- Roles table
CREATE TABLE roles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL
);

INSERT INTO roles (name) VALUES
('admin'),
('cashier'),
('worker');

-- Branches table
CREATE TABLE branches (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);

INSERT INTO branches (name) VALUES
('Main Branch'),
('City Center Branch');

-- Users table
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    role_id INT NOT NULL,
    branch_id INT NOT NULL,
    FOREIGN KEY (role_id) REFERENCES roles(id),
    FOREIGN KEY (branch_id) REFERENCES branches(id)
);

-- Demo users (password is 'password' hashed using PHP password_hash)
INSERT INTO users (username, password, role_id, branch_id) VALUES
('admin', '$2y$10$wH6.QWmJzGhfznzBE8Wjv.BzGZGQej7B5XmCr1ivnNJiyEYSpCOy6', 1, 1),
('cashier', '$2y$10$wH6.QWmJzGhfznzBE8Wjv.BzGZGQej7B5XmCr1ivnNJiyEYSpCOy6', 2, 1),
('worker', '$2y$10$wH6.QWmJzGhfznzBE8Wjv.BzGZGQej7B5XmCr1ivnNJiyEYSpCOy6', 3, 2);

-- Customers table
CREATE TABLE customers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    email VARCHAR(100),
    loyalty_points INT DEFAULT 0,
    account_balance DECIMAL(10,2) DEFAULT 0.00
);

INSERT INTO customers (name, phone, email) VALUES
('John Doe', '123456789', 'john@example.com'),
('Jane Smith', '987654321', 'jane@example.com');

-- Services table
CREATE TABLE services (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(10,2) NOT NULL
);

INSERT INTO services (name, price) VALUES
('Washing', 1.500),
('Ironing', 0.700),
('Dry Cleaning', 2.500);

-- Orders table
CREATE TABLE orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_number VARCHAR(20) NOT NULL UNIQUE,
    customer_id INT,
    branch_id INT,
    user_id INT,
    status VARCHAR(50) DEFAULT 'received',
    total DECIMAL(10,2) DEFAULT 0.00,
    payment_status VARCHAR(50) DEFAULT 'unpaid',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES customers(id),
    FOREIGN KEY (branch_id) REFERENCES branches(id),
    FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Order items
CREATE TABLE order_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    service_id INT NOT NULL,
    quantity INT DEFAULT 1,
    price DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(id),
    FOREIGN KEY (service_id) REFERENCES services(id)
);

-- Demo order
INSERT INTO orders (order_number, customer_id, branch_id, user_id, status, total, payment_status)
VALUES ('ORD001', 1, 1, 2, 'in progress', 4.5, 'partial');

INSERT INTO order_items (order_id, service_id, quantity, price) VALUES
(1, 1, 2, 3.0),
(1, 2, 1, 0.7),
(1, 3, 1, 2.5);
