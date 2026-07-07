FROM eclipse-temurin:17-jre
WORKDIR /app
COPY build/libs/*.jar app.jar
ENV SPRING_PROFILES_ACTIVE=postgres
ENV SERVICE_BINDING_ROOT=/bindings
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
