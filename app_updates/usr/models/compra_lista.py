from sqlalchemy import Column, Integer, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from usr.database.base import Base


class CompraListaItem(Base):
    __tablename__ = "compras_lista"

    id = Column(Integer, primary_key=True)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False, index=True)
    producto = relationship("Producto")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
