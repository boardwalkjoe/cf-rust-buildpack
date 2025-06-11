// src/main.rs
use actix_web::{web, App, HttpResponse, HttpServer, Result};
use std::env;

async fn hello() -> Result<HttpResponse> {
    Ok(HttpResponse::Ok().body("Hello from Rust on Cloud Foundry!"))
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let port = env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let port: u16 = port.parse().expect("PORT must be a number");

    println!("Starting server on port {}", port);

    HttpServer::new(|| {
        App::new()
            .route("/", web::get().to(hello))
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await
}
