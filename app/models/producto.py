from sqlalchemy import Column, Integer, String, Float, Boolean, ForeignKey, DateTime, Text
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from app.database.base import Base

class Producto(Base):
    __tablename__ = "productos"
    # Esta línea permite que si el modelo se importa varias veces no de error
    __table_args__ = {'extend_existing': True}

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(200), nullable=False)
    codigo = Column(String(50), unique=True, nullable=True)
    descripcion = Column(Text, nullable=True)
    
    categoria_id = Column(Integer, ForeignKey("categorias.id"), nullable=False)
    categoria = relationship("Categoria", back_populates="productos")
    
    # NUEVA COLUMNA: Ahora sí se guardará el estado
    es_pesable = Column(Boolean, default=False)
    
    requiere_foto_peso = Column(Boolean, default=False)
    peso_unitario = Column(Float, nullable=True)
    unidad_medida = Column(String(20), default="unidad")
    
    stock_actual = Column(Float, default=0)
    stock_minimo = Column(Float, default=0)
    
    activo = Column(Boolean, default=True)
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    
    movimientos = relationship("Movimiento", back_populates="producto", cascade="all, delete-orphan")

    def __repr__(self):
        return f"<Producto(id={self.id}, nombre='{self.nombre}')>"