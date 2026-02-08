from sqlalchemy import Column, Integer, String, Float, Boolean, ForeignKey, DateTime, Text
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.database.base import Base


class Producto(Base):
    __tablename__ = "productos"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(200), nullable=False)
    codigo = Column(String(50), unique=True, nullable=True)
    descripcion = Column(Text, nullable=True)
    
    # Relación con categoría
    categoria_id = Column(Integer, ForeignKey("categorias.id"), nullable=False)
    categoria = relationship("Categoria", back_populates="productos")
    
    # Atributos del producto
    requiere_foto_peso = Column(Boolean, default=False, comment="True si el producto requiere foto de balanza")
    peso_unitario = Column(Float, nullable=True, comment="Peso unitario en kg para productos unitarios")
    unidad_medida = Column(String(20), default="unidad", comment="unidad, kg, litro, etc.")
    
    # Stock actual
    stock_actual = Column(Float, default=0)
    stock_minimo = Column(Float, default=0)
    
    # Estado
    activo = Column(Boolean, default=True)
    
    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    
    # Relación con movimientos
    movimientos = relationship("Movimiento", back_populates="producto")

    def __repr__(self):
        return f"<Producto(id={self.id}, nombre='{self.nombre}')>"