from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.database.base import Base


class Categoria(Base):
    __tablename__ = "categorias"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(100), nullable=False, unique=True)
    descripcion = Column(String(255), nullable=True)
    imagen = Column(Text, nullable=True)  # Ruta o URL de la imagen
    color = Column(String(20), default="#2196F3")  # Color del botón
    activo = Column(Boolean, default=True)
    
    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    
    # Relación con productos
    productos = relationship("Producto", back_populates="categoria")

    def __repr__(self):
        return f"<Categoria(id={self.id}, nombre='{self.nombre}')>"
